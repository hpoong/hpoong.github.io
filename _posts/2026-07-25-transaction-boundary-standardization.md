---
title: 트랜잭션 경계 표준화
date: 2026-07-25 20:00:00 +0900
categories: [Spring, Transaction]
tags: [spring, transaction, multi-tenant, postgresql, mybatis]
---

## 문제 상황

기존 구조에서는 Mapper를 사용하는 DB 호출이 많았지만, 모든 호출 흐름에 명확한 트랜잭션 경계가 잡혀 있지는 않았다.
간단 집계 기준으로 보면 다음과 같은 상태였다.

- Java 파일: 약 2,600개
- `@Transactional` 포함 파일: 약 100개
- Mapper/DataSource 계열 참조 파일: 약 380개
- Mapper/DataSource 계열 참조지만 `@Transactional` 없는 파일: 약 310개
- mapper/model/param 등을 제외한 구현 후보 중 `@Transactional` 없는 파일: 약 180개

멀티테넌트 구조에서는 `TenantSchemaAspect`가 `TenantContextHolder`의 schema 값을 읽고, DB 커넥션에 다음과 같이 `search_path`를 적용한다.

```sql
SELECT set_config('search_path', ?, true)
```

여기서 세 번째 인자인 `true`는 설정 범위를 현재 트랜잭션으로 제한한다.
즉, `set_config(..., true)`로 설정한 `search_path`는 같은 트랜잭션 안에서 실행되는 쿼리에만 안정적으로 적용된다.

문제는 트랜잭션이 없는 상태에서 MyBatis Mapper가 호출되면, 쿼리마다 커넥션을 빌리고 반납할 수 있다는 점이다.

```text
트랜잭션 없는 DB 호출
├─ TenantSchemaAspect에서 set_config 실행
│  └─ connection A
├─ mapper 쿼리 실행
│  └─ connection B일 수 있음
└─ search_path 적용 보장 없음
```

이 경우 별도로 `set_config`를 실행했더라도, 실제 Mapper 쿼리가 같은 커넥션과 같은 트랜잭션에서 실행된다는 보장이 없다.
결과적으로 다음과 같은 문제가 발생할 수 있었다.

- `search_path`가 실제 쿼리에 적용되지 않을 수 있다.
- 조회 API에서도 tenant schema가 아닌 다른 schema를 바라볼 위험이 있다.
- 여러 계층에 흩어진 `@Transactional` 때문에 트랜잭션 시작 지점이 불명확해진다.
- Facade, Service, Feature 등 여러 위치에서 트랜잭션이 섞이면서 트랜잭션 흐름이 꼬일 수 있다.
- 같은 업무 흐름 안에서도 읽기/쓰기 트랜잭션 기준이 일관되지 않을 수 있다.

## 개선 방법

트랜잭션 경계를 Orchestrator 계층으로 통일했다.
기존처럼 Facade, Service, Feature 등 여러 계층에서 제각각 트랜잭션을 시작하지 않고, 업무 흐름을 조합하는 Orchestrator에서 `@Transactional`을 선언하도록 변경했다.

```text
Controller
└─ Facade
   └─ Orchestrator (@Transactional)
      └─ Feature
         └─ Mapper
```

이 구조에서 Facade는 외부 요청을 받아 Orchestrator로 위임하는 진입 역할을 담당하고, Feature는 실제 기능 단위의 작업을 수행한다.
트랜잭션의 시작과 종료는 Orchestrator가 책임진다.

```java
@Transactional
public void updateSomething(...) {
    feature.validate(...);
    feature.update(...);
    feature.insertHistory(...);
}
```

조회 로직도 동일하게 Orchestrator에서 읽기 전용 트랜잭션을 적용한다.

```java
@Transactional(readOnly = true)
public List<Result> searchSomething(...) {
    return feature.search(...);
}
```

조회 API에도 `@Transactional(readOnly = true)`를 적용하는 이유는 `search_path` 설정이 트랜잭션 범위에서 유지되어야 하기 때문이다.
단순 조회라고 해서 트랜잭션이 필요 없는 것이 아니라, 멀티테넌트 schema routing이 필요한 조회라면 같은 트랜잭션 안에서 `set_config`와 Mapper 쿼리가 실행되어야 한다.

개선 후 흐름은 다음과 같다.

```text
HTTP 요청
├─ TenantInterceptor
│  └─ TenantContextHolder.setSchema(tenant)
├─ Facade 호출
├─ Orchestrator @Transactional 진입
│  ├─ Spring 트랜잭션 시작
│  ├─ TenantSchemaAspect 실행
│  ├─ set_config('search_path', tenant, true)
│  └─ Feature / Mapper 작업 실행
└─ 트랜잭션 commit 또는 rollback
```

이렇게 하면 `set_config(..., true)`와 실제 Mapper 쿼리가 같은 트랜잭션 범위 안에서 실행된다.
또한 트랜잭션 경계가 Orchestrator로 모이기 때문에, 어떤 업무 흐름이 하나의 트랜잭션으로 묶이는지 판단하기 쉬워진다.

## 처리 흐름

기존 흐름은 다음과 같이 트랜잭션 경계가 불명확했다.

```text
Controller
└─ Facade
   ├─ Feature A
   │  └─ Mapper 호출
   ├─ Feature B (@Transactional일 수도 있음)
   │  └─ Mapper 호출
   └─ Feature C
      └─ Mapper 호출

문제:
├─ 어느 시점에 트랜잭션이 시작되는지 불명확
├─ set_config와 mapper 쿼리가 같은 커넥션인지 보장 어려움
└─ 기능별 트랜잭션이 섞이면 업무 흐름이 꼬일 수 있음
```

개선 후 흐름은 다음과 같다.

```text
Controller
└─ Facade
   └─ Orchestrator @Transactional
      ├─ TenantSchemaAspect
      │  └─ search_path 적용
      ├─ Feature A
      │  └─ Mapper 호출
      ├─ Feature B
      │  └─ Mapper 호출
      └─ Feature C
         └─ Mapper 호출

결과:
├─ Orchestrator 진입 시 트랜잭션 시작
├─ 하나의 업무 흐름이 하나의 트랜잭션으로 묶임
├─ set_config와 mapper 쿼리가 같은 트랜잭션 안에서 실행
└─ commit / rollback 기준이 명확해짐
```

조회 로직은 다음과 같이 처리한다.

```text
조회 요청
├─ Facade
├─ Orchestrator @Transactional(readOnly = true)
│  ├─ TenantSchemaAspect
│  ├─ search_path 적용
│  └─ Feature / Mapper 조회
└─ readOnly 트랜잭션 종료
```

## 정리

- `set_config(..., true)`는 현재 트랜잭션 범위에서 `search_path`를 적용한다.
- 트랜잭션이 없으면 `set_config`와 실제 Mapper 쿼리가 같은 커넥션에서 실행된다는 보장이 약해진다.
- 조회 API도 tenant schema routing이 필요하다면 `@Transactional(readOnly = true)`가 필요하다.
- 트랜잭션 경계는 Orchestrator 계층으로 통일했다.
- Facade는 요청 위임, Orchestrator는 업무 흐름과 트랜잭션 경계, Feature는 기능 단위 작업을 담당하도록 역할을 나눴다.
- Orchestrator에 `@Transactional`을 모으면 트랜잭션 시작/종료, commit/rollback 기준이 명확해진다.
