---
title: "트랜잭션 단위로 스키마 설정 (3) - @Scheduled 배치를 테넌트별 트랜잭션으로 실행하도록 바꾸기"
date: 2026-07-25 22:00:00 +0900
categories: [구조 개선, 테넌트 분리]
tags: [spring, transaction, scheduled, batch, multi-tenant, postgresql]
---

[2편](/posts/async-transaction-strategy/)의 `@Async`에 이어, HTTP 요청 밖에서 실행되는 두 번째 경로는 스케줄러다.

## 문제 상황

현재 배치 실행 경로는 `@Scheduled`로 실행되는 스케줄러 경로와, HTTP로 직접 호출하는 수동 실행 경로로 분리되어 있다.

- 스케줄 실행: `BatchScheduler`
- 수동 실행: `BatchController`

수동 HTTP 경로에서는 요청에 담긴 테넌트 정보를 기준으로 테넌트 컨텍스트가 설정된다.
HTTP 요청이 들어오면 `TenantInterceptor`가 요청에서 테넌트를 식별해 `TenantContextHolder`에 저장하고, 이후 Orchestrator의 `@Transactional` 메서드에 진입할 때 `TenantSchemaAspect`가 해당 값을 기준으로 `search_path`를 적용한다.

```text
수동 HTTP 요청
├─ TenantInterceptor가 요청에서 테넌트 식별
├─ TenantContextHolder에 테넌트 스키마 저장
├─ Orchestrator @Transactional 진입
├─ TenantSchemaAspect가 search_path 적용
└─ Feature / Mapper 작업 실행
```

따라서 HTTP 요청으로 들어오는 수동 실행 경로는 테넌트 컨텍스트가 정상적으로 잡힌다.

하지만 `BatchScheduler`는 HTTP 요청으로 실행되지 않는다.
`@Scheduled`는 별도의 스케줄러 스레드에서 직접 실행되기 때문에 `TenantInterceptor`가 실행되지 않고, 테넌트를 식별할 요청 정보도 존재하지 않는다.

```text
스케줄러 실행
├─ @Scheduled 진입
├─ HTTP 요청 아님
├─ 테넌트 정보 없음
├─ TenantInterceptor 실행 안 됨
└─ TenantContextHolder = null
```

이 상태에서 `BatchOrchestrator`의 `@Transactional` 메서드에 진입하면, `TenantSchemaAspect`가 사용할 스키마 값을 찾지 못할 수 있다.
결과적으로 스케줄 경로에서는 `search_path`를 적용하지 못하고 fail-fast가 발생할 수 있다.

## 개선 방법

스케줄러 경로에서는 HTTP 요청이 없기 때문에, 스케줄 진입점에서 테넌트 컨텍스트를 직접 설정해야 한다.
해결 방향은 단순하다.

```text
1. 배치 중복 실행을 막기 위해 advisory lock을 잡는다.
2. public 스키마에서 실행 대상 테넌트 스키마 목록을 조회한다.
3. 조회한 스키마를 테넌트 단위로 순회한다.
4. 테넌트별로 TenantContextHolder.setSchema(schema)를 설정한다.
5. BatchOrchestrator를 호출해 실제 배치 로직을 실행한다.
6. 작업이 끝나면 finally에서 TenantContextHolder.clear()를 호출한다.
```

현재 배치 호출 구조는 다음과 같이 정리되어 있다.

```text
BatchScheduler 또는 BatchController
├─ AdvisoryLockExecutor.executeWithLock(...)
└─ BatchOrchestrator (@Transactional / 조회는 readOnly)
   └─ Feature    (단위 비즈니스 로직, 트랜잭션 없음)
      └─ Mapper
```

수동 HTTP 경로는 `TenantInterceptor`가 테넌트 컨텍스트를 설정하지만, 스케줄러 경로는 동일한 역할을 해 줄 HTTP 계층이 없다.
따라서 `BatchScheduler`가 스케줄러 전용 테넌트 컨텍스트 설정 역할을 직접 담당한다.

### 1. 배치 실행 진입점

각 스케줄 메서드는 실제 배치 로직을 바로 실행하지 않고, `runScheduled(...)`에 배치 이름, lock key, 실행할 job을 전달한다.

```java
private void runScheduled(String jobName, long lockKey, Runnable job) {
    log.info("{} 배치 실행 시작", jobName);
    boolean executed = advisoryLock.executeWithLock(lockKey, () -> runForAllTenants(jobName, job));
    if (!executed) {
        log.info("{} 배치 실행 건너뜀 (다른 인스턴스에서 실행 중 또는 오류)", jobName);
    } else {
        log.info("{} 배치 실행 완료", jobName);
    }
}
```

여기서 `AdvisoryLockExecutor`로 PostgreSQL advisory lock을 먼저 획득한다.
이렇게 하면 동일한 배치가 여러 서버 인스턴스에서 동시에 실행되는 것을 막을 수 있다. lock을 획득한 실행 흐름만 `runForAllTenants(...)`를 통해 테넌트별 배치를 수행한다.

### 2. 테넌트 스키마 목록 조회

스케줄러는 먼저 어떤 테넌트 스키마에 대해 배치를 실행해야 하는지 알아야 한다.
이 목록 조회는 `TenantSchemaCatalog`가 담당한다.

```java
@Transactional(readOnly = true)
public List<String> findTenantSchemas() {
    // 예시: 활성화된 tenant의 schema 이름 목록 조회
    return tenantMapper.findActiveTenantSchemas();
}
```

카탈로그 조회 자체도 DB 접근이기 때문에 스키마 컨텍스트가 필요하다.
그래서 `BatchScheduler`는 bootstrap 스키마인 `public`을 먼저 설정한 뒤 테넌트 스키마 목록을 조회하고, 조회가 끝나면 바로 정리한다.

```java
private List<String> loadTenantSchemas() {
    TenantContextHolder.setSchema(BOOTSTRAP_SCHEMA);
    try {
        return tenantSchemaCatalog.findTenantSchemas();
    } finally {
        TenantContextHolder.clear();
    }
}
```

여기서 `public`은 실제 업무 배치를 실행하기 위한 스키마가 아니라, 배치 대상 테넌트 스키마 목록을 조회하기 위한 bootstrap context다.

### 3. 테넌트별 배치 실행

테넌트 스키마 목록을 가져온 뒤에는 스키마마다 테넌트 컨텍스트를 설정하고 배치를 실행한다.

```java
private void runForAllTenants(String jobName, Runnable job) {
    List<String> schemas = loadTenantSchemas();
    if (schemas.isEmpty()) {
        log.warn("{} 배치: 대상 테넌트 스키마 없음 — 종료", jobName);
        return;
    }

    for (String schema : schemas) {
        TenantContextHolder.setSchema(schema);
        try {
            job.run();
        } catch (Exception e) {
            log.error("{} 배치 실패 — 다음 테넌트 계속", jobName, e);
        } finally {
            TenantContextHolder.clear();
        }
    }
}
```

핵심은 반복문 안의 순서다.

```text
테넌트 스키마 설정
→ job.run()
→ Orchestrator @Transactional 진입
→ TenantSchemaAspect가 search_path 적용
→ finally clear
```

`job.run()` 내부에서는 `BatchOrchestrator`의 `@Transactional` 메서드로 진입한다.
이 시점에는 이미 `TenantContextHolder`에 테넌트 스키마가 들어 있으므로, `TenantSchemaAspect`가 해당 스키마를 기준으로 `search_path`를 설정할 수 있다.

또한 특정 스키마의 배치가 실패하더라도 전체 스케줄을 중단하지 않는다. `catch`에서 실패 로그를 남기고 다음 스키마 처리를 계속한다.

마지막으로 `finally`에서 `TenantContextHolder.clear()`를 호출한다. 스케줄러 스레드는 재사용될 수 있으므로, 이 정리가 빠지면 다음 테넌트 또는 다음 스케줄 실행에 이전 스키마가 남을 수 있다.

정리하면, 스케줄러 경로에서는 스키마 컨텍스트가 두 번 설정된다.

```text
public 스키마
└─ 테넌트 스키마 목록 조회용

테넌트 스키마
└─ 실제 배치 작업 실행용
```

```text
스케줄러 진입점
├─ TenantContextHolder.setSchema(public)
├─ tenant(schema) 목록 조회
├─ TenantContextHolder.clear()
├─ 테넌트별 반복
│  ├─ TenantContextHolder.setSchema(schema)
│  ├─ BatchOrchestrator 호출
│  └─ finally TenantContextHolder.clear()
└─ 다음 테넌트 처리
```

이 방식으로 스케줄러도 수동 HTTP 경로와 동일하게 Orchestrator의 `@Transactional` 진입 시점에 스키마 컨텍스트를 제공할 수 있다.

## 처리 흐름

일일 집계 배치를 예로 들면, 스케줄러 실행은 세 단계로 나뉜다.

```text
1. 중복 실행 방지
   → AdvisoryLockExecutor로 lock 획득
   → 획득 실패 시 이번 실행은 건너뜀

2. 대상 테넌트 조회 (schema = public)
   → TenantSchemaCatalog.findTenantSchemas()
   → 조회 후 clear()

3. 테넌트별 배치 실행 (schema = 각 테넌트)
   → setSchema(tenant)
   → BatchOrchestrator (@Transactional)
   → TenantSchemaAspect가 search_path 적용 후 Feature 실행
   → 실패해도 로그만 남기고 다음 테넌트 진행
   → finally clear()
```

| 단계 | 스키마 컨텍스트 | 트랜잭션 |
|---|---|---|
| 테넌트 목록 조회 | `public` | `@Transactional(readOnly = true)` |
| 테넌트별 배치 실행 | 각 테넌트 스키마 | Orchestrator의 `@Transactional` |

## 정리

- 수동 HTTP 실행은 `TenantInterceptor`가 요청에서 테넌트를 식별해 테넌트 컨텍스트를 설정한다.
- `@Scheduled` 실행은 HTTP 요청이 아니므로 `TenantInterceptor`가 실행되지 않는다.
- 스케줄러는 `public` 스키마로 테넌트 스키마 목록을 조회한 뒤, 테넌트 스키마를 직접 순회하면서 `TenantContextHolder.setSchema(...)`를 설정해야 한다.
- Orchestrator의 `@Transactional` 진입 시점에는 스키마 컨텍스트가 이미 준비되어 있어야 `TenantSchemaAspect`가 `search_path`를 적용할 수 있다.
- 특정 테넌트 배치가 실패하더라도 전체 스케줄이 중단되지 않도록 로그를 남기고 다음 스키마 처리를 계속한다.
- 스케줄러 스레드는 재사용될 수 있으므로 테넌트별 작업이 끝나면 반드시 `TenantContextHolder.clear()`를 호출해야 한다.

다음 글: [트랜잭션 단위로 스키마 설정 (4) - REQUIRES_NEW로 부가 로직 실패가 메인 트랜잭션에 번지지 않게 분리하기](/posts/requires-new-side-effect-transaction/)
