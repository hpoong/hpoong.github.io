---
title: Hazelcast로 여러 Pod의 인증 캐시 통일하기
date: 2026-08-08 12:00:00 +0900
categories: [Spring, 분산 시스템]
tags: [spring, hazelcast, distributed-system, kubernetes, distributed-lock, cache]
---

## 문제 상황

외부 시스템(ERP)이 API를 호출하면, 서버는 먼저 **등록된 호출자인지** 확인한다.
호출자 목록(아이디, 비밀번호 해시, 사용 여부, 접근 가능한 업체)은 DB에 있다.

요청마다 DB를 조회하면 부담이 크기 때문에, 서버는 시작할 때 목록을 **자기 메모리에 복사**해 두고 요청이 오면 메모리에서 확인했다.
DB 내용이 바뀔 수 있으니 **1시간마다 DB를 다시 읽어** 목록을 교체했다.

```java
// 서버 메모리에 보관하는 호출자 목록
private volatile Snapshot snapshot;

// 1시간마다 DB를 다시 읽어 목록을 교체
taskScheduler.scheduleWithFixedDelay(this::refresh, Instant.now().plus(reloadInterval), reloadInterval);
```

Pod가 한 개일 때는 문제가 없었다.
문제는 Kubernetes HPA(Horizontal Pod Autoscaler)로 **CPU 사용률이 임계치를 넘으면 Pod가 자동으로 늘어나도록** 설정한 뒤에 생겼다.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: external-api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: external-api
  minReplicas: 1          # 평소에는 Pod 1개
  maxReplicas: 3          # 부하가 몰리면 최대 3개까지
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70   # Pod 평균 CPU 사용률이 70%를 넘으면 Pod 추가
```

CPU 사용률은 Deployment에 설정한 `resources.requests.cpu` 대비 비율로 계산된다.

새 Pod는 뜨는 순간 DB에서 호출자 목록을 읽고, 그때부터 1시간마다 다시 읽는다.
즉 **Pod마다 목록을 읽은 시각이 기동 시각에 따라 달라진다.**

그날 오전에는 Pod 1이 08:00부터 떠 있었고, 요청이 몰려 CPU가 임계치를 넘자 HPA가 09:20에 Pod 2, 09:40에 Pod 3을 추가했다.
그 사이 09:30에 신규 ERP 연동 업체의 호출자를 등록했다.

| Pod | 기동 | 마지막으로 목록을 읽은 시각 | 다음 갱신 | 09:45 요청 | 10:10 요청 |
| --- | --- | --- | --- | --- | --- |
| Pod 1 | 08:00 | 09:00 | 10:00 | 거절 | 허용 |
| Pod 2 | 09:20 | 09:20 (기동 시) | 10:20 | 거절 | 거절 |
| Pod 3 | 09:40 | 09:40 (기동 시) | 10:40 | 허용 | 허용 |

등록 직후 ERP에서 **같은 인증 정보로 호출했는데 일부 요청만 401로 거절되는** 문제가 있었다.
Pod별 인증 로그를 나눠 보니, 등록 이후에 뜬 Pod 3만 새 호출자를 알고 있었고 나머지 Pod는 등록 전 목록을 들고 있었다.
로드밸런서가 **어느 Pod로 보냈느냐에 따라** 성공과 실패가 갈렸고, 세 Pod가 모두 새 목록을 갖게 된 10:20까지 50분 동안 거절이 섞여 나왔다.

반대로 호출자를 사용 중지하는 경우에는, 갱신이 늦은 Pod가 **막아야 할 요청을 계속 허용**하게 된다.

- **데이터 불일치:** Pod마다 독립된 로컬 캐시를 사용
- **갱신 시점 차이:** Pod별 스케줄 실행 시각이 달라 DB 변경이 다른 시점에 반영
- **인증 결과 불일치:** 같은 요청에 Pod마다 다른 결과 반환
- **DB 조회 증가:** Pod가 늘수록 갱신 작업과 DB 조회도 함께 증가

HPA를 쓰는 한 Pod는 언제든 다른 시각에 뜬다. 갱신 주기를 줄이는 것만으로는 Pod 간 차이가 사라지지 않는다.
**모든 Pod가 같은 목록을 보고, 갱신은 한곳에서 하는 구조**가 필요했다.

보통은 Redis 같은 공유 캐시를 쓰지만, 운영 환경에서는 Redis를 쓸 수 없었다.

## 해결 방향: Hazelcast

Hazelcast는 **애플리케이션 안에 라이브러리로 넣어 쓰는 분산 캐시**다.
별도 캐시 서버 없이, 서버들이 네트워크로 서로를 찾아 하나의 클러스터가 되고 데이터를 공유한다.

이번에 쓴 기능은 두 가지다.

| 기능 | 하는 일 |
| --- | --- |
| `ReplicatedMap` | 모든 서버에 **같은 복사본**을 유지한다. 한 서버가 값을 바꾸면 나머지 서버에도 반영된다. |
| 분산 락 | 여러 서버 중 **한 대만** 특정 작업을 하도록 정한다. |

운영 환경에서는 Kubernetes 서비스 주소로 서로를 찾도록 설정했다.

```yaml
hazelcast:
  cluster-name: external-api-prd   # 같은 이름끼리만 하나의 클러스터가 된다
  network:
    join:
      kubernetes:
        enabled: true
        service-dns: external-api-hz.<namespace>.svc.cluster.local   # 이 주소로 다른 서버 목록을 조회
```

## 개선 방법

### 1. 호출자 목록을 공유 캐시에 둔다

```java
this.cache = hazelcastInstance.getReplicatedMap("api-client-cache");
```

이제 모든 서버가 **같은 캐시**를 본다.
`ReplicatedMap`은 서버마다 복사본이 있어서, 조회할 때 다른 서버에 묻지 않고 자기 메모리에서 바로 읽는다.
모든 API 요청이 호출자를 확인하므로, 조회가 빠른 이 방식을 골랐다.

### 2. DB 재조회는 한 대만 한다

모든 서버가 1시간마다 갱신을 시도하는 것은 그대로 두었다.
대신 갱신 전에 **같은 이름의 락**을 잡게 하고, 락을 잡은 서버만 DB를 읽는다.
락을 못 잡은 서버는 다른 서버가 갱신 중이라는 뜻이므로 기다리지 않고 넘어간다.

```java
// 기다리지 않고(0) 락을 시도. 잡은 서버가 죽어도 1분 뒤 자동으로 풀린다.
if (!locks.tryLock("reload", 0, TimeUnit.MILLISECONDS, 1, TimeUnit.MINUTES)) {
    return; // 다른 서버가 갱신 중
}
```

### 3. 최근에 갱신했으면 건너뛴다

락만으로는 부족했다. 서버마다 갱신 시각이 달라서, 차례로 락을 잡으면 결국 **서버 수만큼 DB를 읽는다.**

그래서 캐시에 **마지막 갱신 시각**을 함께 저장하고, 갱신 주기의 절반(30분) 안에 누군가 갱신했다면 건너뛰도록 했다.

```java
Duration elapsed = Duration.between(snapshot().loadedAt(), Instant.now());
if (elapsed.compareTo(reloadInterval.dividedBy(2)) < 0) {
    return; // 30분 안에 다른 서버가 이미 갱신함
}
```

적용 후 같은 구성(08:00, 09:20, 09:40 기동)에서 Pod 3대의 갱신 로그는 다음과 같았다. 각 Pod의 스케줄은 기동 시각에 따라 10:00, 10:20, 10:40에 돌았다.

| 시각 | Pod | 마지막 갱신 후 경과 | 결과 |
| --- | --- | --- | --- |
| 10:00 | Pod 1 | 60분 (09:00 갱신) | DB 읽음 |
| 10:20 | Pod 2 | 20분 | 건너뜀 |
| 10:40 | Pod 3 | 40분 | DB 읽음 |
| 11:00 | Pod 1 | 20분 | 건너뜀 |

이전에는 Pod 3대가 각자 1시간에 한 번씩, 모두 3번 DB를 읽었다.
지금은 Pod가 몇 개로 늘어도 DB 조회가 **1시간에 최대 2번**이다.

### 4. 목록은 통째로 교체한다

호출자를 한 명씩 캐시에 넣으면, 갱신 도중 일부만 바뀐 목록을 다른 서버가 읽을 수 있다.
그래서 목록 전체를 하나의 값으로 묶어 **한 번에 교체**했다.

```java
// 목록 전체 + 마지막 갱신 시각을 하나로 묶은 값
record Snapshot(Map<String, ApiClient> clients, Map<String, byte[]> hashes, Set<String> warnings,
        Instant loadedAt) implements Serializable {
}

cache.put("snapshot", newSnapshot); // 한 번에 교체
```

다른 서버로 복사될 때 직렬화가 필요하므로 `Serializable`을 구현했다.

### 5. 요청 처리 중에는 캐시만 본다

```java
Snapshot snapshot = cache.get("snapshot");
```

요청 처리 중에는 DB에 접근하지 않는다.
DB 조회에 실패하면 기존 캐시를 그대로 두므로, DB에 잠시 문제가 생겨도 인증은 계속 동작한다.

## 결과

적용 후에도 HPA는 같은 방식으로 09:20, 09:40에 Pod를 추가했다.
달라진 점은 **새 Pod가 DB를 읽지 않고 클러스터에 합류해, 이미 공유 캐시에 있는 목록을 그대로 받는다**는 것이다.
그래서 Pod가 언제 떴든 세 Pod는 같은 목록(09:00에 Pod 1이 읽은 목록)을 들고 있었다.

다시 09:30에 신규 호출자를 등록했을 때, 다음 DB 갱신은 10:00에 Pod 1이 했다.

| Pod | 기동 | 09:30 ~ 10:00 | 10:00 이후 |
| --- | --- | --- | --- |
| Pod 1 | 08:00 | 거절 | 허용 |
| Pod 2 | 09:20 | 거절 | 허용 |
| Pod 3 | 09:40 | 거절 | 허용 |

DB 변경이 반영되기까지는 여전히 최대 1시간이 걸린다.
하지만 **모든 Pod가 같은 시점에 같은 결과**를 낸다. 같은 인증 정보로 일부만 거절되는 일은 없어졌고, 10:00 이후에는 어느 Pod로 요청이 가도 허용됐다.

## 처리 흐름

```text
[1시간마다, 모든 서버]
├─ 락을 못 잡음 → 넘어감 (다른 서버가 갱신 중)
└─ 락을 잡음
   ├─ 30분 안에 누가 갱신함 → 넘어감
   └─ DB에서 목록 읽기
      ├─ 실패 → 기존 캐시 유지
      └─ 성공 → 공유 캐시 교체 → 모든 서버에 같은 목록이 복사됨

[API 요청이 올 때, 모든 서버]
└─ 공유 캐시(자기 서버의 복사본)에서 호출자 확인
```

## 정리

- HPA로 Pod가 서로 다른 시각에 뜨면, Pod마다 따로 들고 있는 메모리 캐시는 **내용이 서로 달라진다.**
- Redis를 쓸 수 없다면 Hazelcast를 애플리케이션에 넣어 **서버끼리 캐시를 공유**할 수 있다.
- 자주 읽고 크기가 작은 데이터는 `ReplicatedMap`을 쓰면 모든 서버가 같은 값을 빠르게 읽는다.
- **분산 락**으로 DB를 읽는 서버를 한 대로 정하고 **마지막 갱신 시각**을 함께 보면, 서버가 늘어도 DB 부담이 늘지 않는다.
- 캐시 값은 **통째로 교체**해야 갱신 도중의 어중간한 상태가 보이지 않는다.
- 이 구조가 없애는 것은 **서버 간 불일치**다. DB 변경 반영까지의 지연(최대 갱신 주기)은 그대로이므로, 더 빨리 반영하려면 갱신 주기를 줄인다.

> 서버들이 서로를 찾으려면 Kubernetes에 headless Service(`publishNotReadyAddresses: true`)가 있어야 한다. 없으면 각 서버가 혼자 떠서, 실행은 되지만 캐시를 공유하지 않는다.
{: .prompt-warning }

> 캐시에는 비밀번호 해시가 들어 있고 서버 간에 복사된다. 무료 버전 Hazelcast는 서버 간 통신을 암호화하지 않으므로, 클러스터 포트(5701)는 같은 서비스의 서버끼리만 통신하도록 막아야 한다.
{: .prompt-warning }
