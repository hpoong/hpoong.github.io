---
title: "@Async에서 트랜잭션 전략"
date: 2026-07-25 21:00:00 +0900
categories: [Spring, Transaction]
tags: [spring, transaction, async, multi-tenant, threadlocal]
---

## 문제 상황

현재 멀티테넌트 구조에서는 요청마다 사용하는 스키마 정보가 `TenantContextHolder`의 `ThreadLocal`에 저장된다.
일반적인 동기 처리에서는 HTTP 요청 스레드 안에서 Controller, Facade, Orchestrator, Feature, Mapper 흐름이 이어지기 때문에 같은 스레드의 `ThreadLocal` 값을 계속 사용할 수 있다.

```text
HTTP 스레드
├─ tenantId 확인
├─ TenantContextHolder = tenant_a
├─ @Transactional 진입
├─ search_path = tenant_a 설정
└─ mapper 작업 실행
```

하지만 `@Async`를 사용하면 실제 작업은 HTTP 요청 스레드가 아니라 별도의 워커 스레드에서 실행된다.
`ThreadLocal`은 스레드마다 별도의 저장 공간을 사용하고 스레드 간에 자동으로 전달되지 않기 때문에, HTTP 스레드에 있던 스키마 정보가 비동기 스레드에서는 사라진다.

```text
HTTP 스레드
TenantContextHolder = tenant_a

비동기 스레드
TenantContextHolder = null
```

이 상태에서 비동기 작업 내부의 `@Transactional` 로직이 실행되면 `TenantSchemaAspect`가 조회할 스키마 값이 없기 때문에 올바른 `search_path`를 설정할 수 없다.
결과적으로 다음과 같은 문제가 발생할 수 있다.

- 비동기 작업이 대상 테넌트 스키마가 아닌 기본 스키마를 바라볼 수 있다.
- mapper 실행 시 테이블을 찾지 못하거나 잘못된 스키마의 데이터를 조회할 수 있다.
- 엑셀 업로드, 승인 처리처럼 백그라운드에서 실행되는 작업이 요청한 테넌트와 분리될 수 있다.
- 스레드 풀을 재사용하는 구조에서 `ThreadLocal`을 정리하지 않으면 이전 요청의 스키마가 다음 작업에 남을 수 있다.

따라서 비동기 작업을 실행할 때는 HTTP 요청 스레드의 스키마 컨텍스트를 워커 스레드로 명시적으로 전달하고, 작업 종료 후 반드시 제거해야 한다.

## 개선 방법

가장 중요한 부분은 `setTaskDecorator`다.

```java
@Bean(name = "tenantTaskExecutor")
public Executor tenantTaskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(2);
    executor.setMaxPoolSize(5);
    executor.setQueueCapacity(100);
    executor.setThreadNamePrefix("tenant-executor-");
    executor.setTaskDecorator(new TenantContextTaskDecorator()); // 핵심
    executor.initialize();
    return executor;
}
```

`TenantContextTaskDecorator`는 비동기 작업이 넘어가기 전에 현재 스키마를 캡처하고, 비동기 스레드에 다시 설정하는 역할을 한다.

```text
HTTP 스레드
tenant_a
    ↓ 캡처
TenantContextTaskDecorator
    ↓ 전달
tenant-executor-1
tenant_a
```

예시 구현은 다음과 같다.

```java
public class TenantContextTaskDecorator implements TaskDecorator {

    @Override
    public Runnable decorate(Runnable runnable) {
        String schema = TenantContextHolder.getSchema();

        return () -> {
            try {
                TenantContextHolder.setSchema(schema);
                runnable.run();
            } finally {
                TenantContextHolder.clear();
            }
        };
    }
}
```

## 처리 흐름

작동 순서는 다음과 같다.

```text
1. HTTP 스레드에서 tenantId 확인
2. TaskDecorator가 schema 값 저장
3. 비동기 스레드 시작
4. 비동기 스레드에 schema 설정
5. 실제 엑셀 업로드 실행
6. 작업 종료 후 ThreadLocal 제거
```

승인 처리를 비동기로 실행하는 경우, 웹 스레드는 작업을 제출만 하고 빠르게 응답하며 실제 트랜잭션은 워커 스레드에서 시작된다.

```text
1) 웹 스레드 (응답 빨리 반환)
   Facade.submitApproval
     → jobId 발급
     → Orchestrator.approveAsync       ← TX 없음, "시작만"
       → Feature.approveAsync(@Async)  ← 여기까지는 submit만
   → 클라이언트에 jobId 반환

2) 워커 스레드 (백그라운드)
   TenantContextTaskDecorator가 schema 복원
   Feature.approveAsync 본문 실행
     → job PROCESSING
     → Orchestrator.approve(@Transactional)  ← 여기서 TX + search_path
         → Feature.approve (실제 mapper 작업)
     → job COMPLETED
```

워커 스레드 안에서 스키마가 실제 DB에 적용되는 시점은 다음과 같다.

```text
1. TenantContextTaskDecorator
   → TenantContextHolder.setSchema("tenant_a")   // ThreadLocal만 설정

2. Orchestrator.approve(@Transactional) 진입
   → Spring이 TX 시작
   → TenantSchemaAspect @Before 실행

3. TenantSchemaAspect
   → TenantContextHolder.getSchema()  // "tenant_a"
   → SELECT set_config('search_path', 'tenant_a', true)  // 여기서 실제 DB 적용
```

## 정리

마지막의 `clear()`가 특히 중요하다.
스레드 풀은 스레드를 재사용하기 때문에 제거하지 않으면 다음 요청이 이전 사용자의 스키마를 바라보는 심각한 문제가 생길 수 있다.

- `ThreadLocal`은 스레드마다 별도의 저장 공간을 사용한다.
- `@Async`는 HTTP 요청 스레드가 아닌 별도의 워커 스레드에서 실행된다.
- 비동기 스레드에서 올바른 스키마를 사용하려면 `TaskDecorator`로 스키마 컨텍스트를 전달해야 한다.
- 트랜잭션은 웹 스레드가 아니라 워커 스레드에서 호출하는 Orchestrator의 `@Transactional`에서 시작한다.
- 작업 종료 후 `TenantContextHolder.clear()`를 호출해 스레드 풀에 이전 스키마가 남지 않도록 해야 한다.
