---
title: Hazelcast 개념 정리
date: 2026-08-08 13:00:00 +0900
categories: [Spring, 분산 시스템]
tags: [spring, hazelcast, distributed-system, kubernetes, cache]
---

## 문제 상황

서버가 한 대일 때는 자주 쓰는 데이터를 **서버 메모리에 두면** 충분하다.
하지만 Kubernetes에서 Pod가 여러 개로 늘어나면, Pod마다 자기 메모리를 따로 가진다.

```text
Pod 1 메모리: 목록 A
Pod 2 메모리: 목록 A
Pod 3 메모리: 목록 B   ← 다른 시각에 읽어서 내용이 다름
```

같은 요청이라도 어느 Pod로 가느냐에 따라 결과가 달라진다.
Pod들이 **같은 데이터를 함께 보는 방법**이 필요하다.

보통은 Redis 같은 별도 캐시 서버를 둔다. 그런데 운영 환경에 따라 캐시 서버를 새로 띄울 수 없는 경우가 있다.

## 해결 방향: Hazelcast

Hazelcast는 **애플리케이션 안에 라이브러리로 넣어 쓰는 분산 메모리 저장소**다.
별도 서버를 설치하지 않고, 애플리케이션들이 서로를 찾아 하나로 묶인 뒤 메모리 데이터를 공유한다.

| 구분 | Redis | Hazelcast (임베디드) |
| --- | --- | --- |
| 실행 위치 | 별도 캐시 서버 | 애플리케이션 안 |
| 설치·운영 | 서버를 따로 띄우고 관리 | 의존성 추가와 설정만 |
| 데이터 위치 | 캐시 서버 메모리 | 애플리케이션(Pod)들의 메모리 |
| 조회 | 항상 네트워크를 거침 | 자료구조에 따라 자기 메모리에서 바로 읽음 |

Hazelcast도 별도 서버로 띄우고 애플리케이션이 접속하는 방식(클라이언트-서버)을 지원하지만, 이 글은 애플리케이션 안에 넣는 **임베디드 방식**을 다룬다.

## 핵심 개념

### 1. 클러스터와 멤버

Hazelcast를 넣은 애플리케이션 하나하나를 **멤버**라고 부른다. 멤버들이 묶인 하나의 묶음이 **클러스터**다.

```text
클러스터: order-service-prd
├─ 멤버 (Pod 1)
├─ 멤버 (Pod 2)
└─ 멤버 (Pod 3)
```

- 같은 `cluster-name`을 가진 멤버끼리만 하나의 클러스터가 된다.
- 새 Pod가 뜨면 클러스터에 합류하고, Pod가 내려가면 클러스터에서 빠진다.
- 멤버끼리는 **5701 포트**로 통신한다.

### 2. 멤버끼리 서로 찾기

클러스터를 만들려면 멤버가 서로의 주소를 알아야 한다.
Kubernetes에서는 **서비스 DNS를 조회해 다른 Pod 목록을 얻는 방식**을 많이 쓴다.

```yaml
# hazelcast.yaml
hazelcast:
  cluster-name: order-service-prd
  network:
    join:
      multicast:
        enabled: false     # Kubernetes에서는 멀티캐스트를 쓰지 않는다
      kubernetes:
        enabled: true
        service-dns: order-service-hz.<namespace>.svc.cluster.local
```

이 DNS가 Pod들의 IP를 돌려주려면 **headless Service**가 있어야 한다.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: order-service-hz
spec:
  clusterIP: None                  # headless: Pod IP를 그대로 돌려준다
  publishNotReadyAddresses: true   # 아직 준비 전인 Pod도 목록에 포함
  selector:
    app: order-service
  ports:
    - name: hazelcast
      port: 5701
```

`publishNotReadyAddresses: true`가 없으면, Pod가 뜨는 도중(Readiness 통과 전)에는 DNS에 나오지 않아 서로를 찾지 못한다.

### 3. 데이터를 담는 자료구조

자주 쓰는 Map 두 가지는 **데이터를 어디에 두느냐**가 다르다.

| 구분 | `IMap` | `ReplicatedMap` |
| --- | --- | --- |
| 데이터 위치 | 여러 멤버에 **나눠서** 저장 | 모든 멤버에 **전체 복사본** 저장 |
| 조회 | 데이터가 다른 멤버에 있으면 네트워크로 가져옴 | 항상 자기 메모리에서 읽음 |
| 쓰기 | 담당 멤버에 저장하고 백업 멤버에 복사 | 모든 멤버에 복사 |
| 맞는 데이터 | 크고 자주 바뀌는 데이터 | 작고 자주 읽는 데이터 |

```java
IMap<String, Order> orders = hazelcast.getMap("orders");                       // 나눠서 저장
ReplicatedMap<String, Snapshot> clients = hazelcast.getReplicatedMap("clients"); // 전체 복사
```

`ReplicatedMap`은 한 멤버에서 쓴 값이 **다른 멤버에 비동기로 복사**된다.
쓴 직후 아주 짧은 순간에는 멤버마다 값이 다를 수 있으니, 한 번 쓴 값이 즉시 모든 곳에 보여야 하는 데이터에는 맞지 않는다.

### 4. 분산 락

여러 Pod 중 **한 대만** 어떤 작업을 해야 할 때 쓴다. `IMap`의 키 단위 락을 쓰면 클러스터 전체에서 같은 키의 락은 한 멤버만 잡을 수 있다.

```java
IMap<String, Boolean> locks = hazelcast.getMap("job-locks");

// 기다리지 않고(0) 시도. 잡은 Pod가 죽어도 1분 뒤 자동으로 풀린다.
if (locks.tryLock("daily-job", 0, TimeUnit.MILLISECONDS, 1, TimeUnit.MINUTES)) {
    try {
        runJob();
    } finally {
        locks.unlock("daily-job");
    }
}
```

마지막 인자(lease time)는 **락을 잡은 Pod가 죽었을 때 대비**다. 이 시간이 지나면 락이 자동으로 풀린다.
작업이 이 시간보다 오래 걸리면 락이 먼저 풀려 다른 Pod가 같은 작업을 시작할 수 있으므로, 작업 시간보다 넉넉하게 잡는다.

### 5. 직렬화

멤버끼리 데이터를 주고받으려면 객체를 바이트로 바꿔야 한다.
그래서 Map에 넣는 값은 **직렬화할 수 있어야** 한다.

```java
record Snapshot(Map<String, ApiClient> clients, Instant loadedAt) implements Serializable {
}
```

값 안에 들어 있는 객체(`ApiClient` 등)도 모두 직렬화할 수 있어야 한다. 하나라도 빠지면 다른 멤버로 복사할 때 예외가 난다.

## Spring Boot에서 사용하기

의존성을 추가하고 클래스패스에 `hazelcast.yaml`을 두면, Spring Boot가 `HazelcastInstance`를 Bean으로 만들어 준다.

```groovy
implementation 'com.hazelcast:hazelcast'
```

설정 파일이 기본 위치가 아니면 경로를 지정한다.

```yaml
# application.yml
spring:
  hazelcast:
    config: classpath:hazelcast/hazelcast-prd.yaml
```

이후에는 `HazelcastInstance`를 주입받아 쓴다.

```java
@Component
public class ClientCache {

    private final ReplicatedMap<String, Snapshot> cache;

    public ClientCache(HazelcastInstance hazelcast) {
        this.cache = hazelcast.getReplicatedMap("clients");
    }
}
```

## 처리 흐름

```text
[Pod가 뜰 때]
├─ HazelcastInstance 생성
├─ 서비스 DNS로 다른 Pod 목록 조회
├─ 클러스터가 있으면 합류 → ReplicatedMap 데이터를 복사받음
└─ 없으면 새 클러스터 시작 (첫 멤버)

[데이터를 쓸 때]
└─ 한 멤버에서 put → 다른 멤버에 복사

[데이터를 읽을 때]
├─ ReplicatedMap → 자기 메모리에서 바로 읽음
└─ IMap → 담당 멤버에서 읽음 (다른 멤버면 네트워크)

[Pod가 내려갈 때]
└─ 클러스터에서 빠짐 → IMap은 백업으로 데이터 유지
```

## 정리

- Pod가 여러 개면 서버 메모리 캐시는 Pod마다 달라질 수 있다.
- Hazelcast는 애플리케이션 안에 넣어 **Pod끼리 메모리 데이터를 공유**하게 해 주는 라이브러리다. 별도 캐시 서버가 필요 없다.
- 같은 `cluster-name`의 멤버가 하나의 클러스터가 되고, Kubernetes에서는 **headless Service DNS**로 서로를 찾는다.
- 크고 자주 바뀌는 데이터는 `IMap`(나눠 저장), 작고 자주 읽는 데이터는 `ReplicatedMap`(전체 복사)을 쓴다.
- 한 Pod만 작업해야 할 때는 **분산 락**을 쓰고, 락을 잡은 Pod가 죽을 때를 대비해 lease time을 둔다.
- Map에 넣는 값은 안쪽 객체까지 모두 **직렬화할 수 있어야** 한다.

실제 적용 사례는 [Hazelcast로 여러 Pod의 인증 캐시 통일하기](/posts/hazelcast-shared-auth-cache/)에 정리했다.

> 무료 버전 Hazelcast는 멤버 간 통신을 암호화하지 않는다. 민감한 데이터를 담는다면 5701 포트는 같은 서비스의 Pod끼리만 통신하도록 네트워크 정책으로 막아야 한다.
{: .prompt-warning }
