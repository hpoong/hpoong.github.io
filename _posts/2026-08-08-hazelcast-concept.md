---
title: Pod 간 인증 캐시 통일하기 (2) - 캐시 서버 없이 Hazelcast를 도입하며 검토한 것
date: 2026-08-08 13:00:00 +0900
categories: [구조 개선, 인증 캐시 공유]
tags: [spring, hazelcast, distributed-system, kubernetes, cache]
---

[1편](/posts/hazelcast-shared-auth-cache/)에서는 HPA로 늘어난 Pod마다 인증 캐시가 달라지는 문제를 Hazelcast로 해결했다.
이 글은 그 과정에서 검토한 선택지와, 각 설정을 그렇게 정한 이유를 정리한다.

## 1. 왜 Redis가 아니라 임베디드 Hazelcast인가

Pod끼리 캐시를 공유하는 보통의 방법은 Redis 같은 별도 캐시 서버다.
하지만 Redis를 띄우려면 **추가 비용**이 들어서 운영 환경에 올릴 수 없었다.

Hazelcast는 **애플리케이션 안에 라이브러리로 넣어 쓰는 분산 메모리 저장소**다.
별도 서버 없이, 애플리케이션들이 서로를 찾아 하나로 묶인 뒤 메모리 데이터를 공유한다.

| 구분 | Redis | Hazelcast (임베디드) |
| --- | --- | --- |
| 실행 위치 | 별도 캐시 서버 | 애플리케이션 안 |
| 설치·운영 | 서버를 따로 띄우고 관리 | 의존성 추가와 설정만 |
| 데이터 위치 | 캐시 서버 메모리 | 애플리케이션(Pod)들의 메모리 |
| 조회 | 항상 네트워크를 거침 | 자료구조에 따라 자기 메모리에서 바로 읽음 |

Hazelcast도 별도 서버로 띄우는 방식(클라이언트-서버)을 지원하지만, 그러면 Redis와 같은 비용 문제가 생기므로 **임베디드 방식**을 골랐다.

도입은 의존성 추가와 설정 파일 지정으로 끝난다. Spring Boot가 `HazelcastInstance`를 Bean으로 만들어 준다.

```groovy
implementation 'com.hazelcast:hazelcast'
```

```yaml
# application.yml
spring:
  hazelcast:
    config: classpath:hazelcast/hazelcast-prd.yaml
```

## 2. 왜 IMap이 아니라 ReplicatedMap인가

Hazelcast에서 자주 쓰는 Map 두 가지는 **데이터를 어디에 두느냐**가 다르다.

| 구분 | `IMap` | `ReplicatedMap` |
| --- | --- | --- |
| 데이터 위치 | 여러 멤버에 **나눠서** 저장 | 모든 멤버에 **전체 복사본** 저장 |
| 조회 | 데이터가 다른 멤버에 있으면 네트워크로 가져옴 | 항상 자기 메모리에서 읽음 |
| 쓰기 | 담당 멤버에 저장하고 백업 멤버에 복사 | 모든 멤버에 복사 |
| 맞는 데이터 | 크고 자주 바뀌는 데이터 | 작고 자주 읽는 데이터 |

호출자 목록은 **작고, 1시간에 한 번 바뀌고, 모든 API 요청마다 읽는다.**
그래서 요청마다 네트워크를 타지 않는 `ReplicatedMap`을 골랐다.

```java
this.cache = hazelcastInstance.getReplicatedMap("api-client-cache");
```

`ReplicatedMap`은 한 멤버에서 쓴 값이 **다른 멤버에 비동기로 복사**된다.
쓴 직후 아주 짧은 순간에는 멤버마다 값이 다를 수 있지만, 호출자 목록은 원래 갱신까지 최대 1시간이 걸리는 데이터라 문제가 되지 않는다.

## 3. Pod끼리 서로 찾게 하려면

Hazelcast를 넣은 애플리케이션 하나하나를 **멤버**, 멤버들의 묶음을 **클러스터**라고 부른다.

```text
클러스터: external-api-prd
├─ 멤버 (Pod 1)
├─ 멤버 (Pod 2)
└─ 멤버 (Pod 3)
```

- 같은 `cluster-name`을 가진 멤버끼리만 하나의 클러스터가 된다.
- 새 Pod가 뜨면 클러스터에 합류하고, Pod가 내려가면 클러스터에서 빠진다.
- 멤버끼리는 **5701 포트**로 통신한다.

멤버가 서로의 주소를 알도록, Kubernetes **서비스 DNS를 조회해 다른 Pod 목록을 얻는 방식**을 썼다.

```yaml
# hazelcast-prd.yaml
hazelcast:
  cluster-name: external-api-prd
  network:
    join:
      multicast:
        enabled: false     # Kubernetes에서는 멀티캐스트를 쓰지 않는다
      kubernetes:
        enabled: true
        service-dns: external-api-hz.<namespace>.svc.cluster.local
```

이 DNS가 Pod들의 IP를 돌려주려면 **headless Service**가 있어야 한다.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-api-hz
spec:
  clusterIP: None                  # headless: Pod IP를 그대로 돌려준다
  publishNotReadyAddresses: true   # 아직 준비 전인 Pod도 목록에 포함
  selector:
    app: external-api
  ports:
    - name: hazelcast
      port: 5701
```

`publishNotReadyAddresses: true`가 없으면, Pod가 뜨는 도중(Readiness 통과 전)에는 DNS에 나오지 않아 서로를 찾지 못한다.
그러면 각 Pod가 혼자 클러스터를 만들어, 실행은 되지만 캐시를 공유하지 않는다.

## 4. 락 lease time을 정한 이유

DB 재조회를 한 Pod만 하도록 `IMap`의 키 단위 락을 썼다. 클러스터 전체에서 같은 키의 락은 한 멤버만 잡을 수 있다.

```java
// 기다리지 않고(0) 시도. 잡은 Pod가 죽어도 1분 뒤 자동으로 풀린다.
if (!locks.tryLock("reload", 0, TimeUnit.MILLISECONDS, 1, TimeUnit.MINUTES)) {
    return; // 다른 Pod가 갱신 중
}
```

마지막 인자(lease time)는 **락을 잡은 Pod가 갱신 도중 죽었을 때 대비**다. 이 시간이 지나면 락이 자동으로 풀린다.
너무 짧으면 갱신이 끝나기 전에 락이 풀려 다른 Pod가 같은 갱신을 시작하므로, 갱신 작업(DB 조회 + 캐시 교체)보다 넉넉한 1분으로 잡았다.

## 5. Snapshot 직렬화

멤버끼리 데이터를 주고받으려면 객체를 바이트로 바꿔야 한다.
그래서 캐시에 넣는 `Snapshot`은 **직렬화할 수 있어야** 한다.

```java
record Snapshot(Map<String, ApiClient> clients, Map<String, byte[]> hashes, Set<String> warnings,
        Instant loadedAt) implements Serializable {
}
```

값 안에 들어 있는 객체(`ApiClient` 등)도 모두 직렬화할 수 있어야 한다. 하나라도 빠지면 다른 멤버로 복사할 때 예외가 난다.

## 처리 흐름

```text
[Pod가 뜰 때]
├─ HazelcastInstance 생성
├─ 서비스 DNS로 다른 Pod 목록 조회
├─ 클러스터가 있으면 합류 → ReplicatedMap 데이터를 복사받음
└─ 없으면 새 클러스터 시작 (첫 멤버)

[캐시를 교체할 때]
└─ 한 Pod에서 put → 다른 Pod에 복사

[캐시를 읽을 때]
└─ 자기 메모리의 복사본에서 바로 읽음

[Pod가 내려갈 때]
└─ 클러스터에서 빠짐 → 다른 Pod에 복사본이 남아 있음
```

## 정리

- Redis는 추가 비용 때문에 쓸 수 없어서, 애플리케이션 안에 넣는 **임베디드 Hazelcast**를 골랐다.
- 호출자 목록은 작고 자주 읽으므로, 모든 Pod에 복사본을 두는 **`ReplicatedMap`**을 썼다.
- Pod끼리 찾으려면 **headless Service**와 `publishNotReadyAddresses: true`가 필요하다.
- 락 lease time은 갱신 작업보다 넉넉하게 잡아, Pod가 죽어도 락이 남지 않게 했다.
- 캐시에 넣는 값은 안쪽 객체까지 모두 **직렬화할 수 있어야** 한다.

> 무료 버전 Hazelcast는 멤버 간 통신을 암호화하지 않는다. 캐시에 비밀번호 해시가 들어 있으므로, 5701 포트는 같은 서비스의 Pod끼리만 통신하도록 네트워크 정책으로 막아야 한다.
{: .prompt-warning }
