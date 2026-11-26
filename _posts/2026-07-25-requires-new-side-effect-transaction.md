---
title: "트랜잭션 단위로 스키마 설정 (4) - REQUIRES_NEW로 부가 로직 실패가 메인 트랜잭션에 번지지 않게 분리하기"
date: 2026-07-25 23:00:00 +0900
categories: [구조 개선, 테넌트 분리]
tags: [spring, transaction, propagation, requires-new]
---

[1편](/posts/transaction-boundary-standardization/)의 규칙은 "트랜잭션은 Orchestrator에서만 시작한다"였다. 이 글은 그 규칙의 예외로, 하나의 업무 안에서 트랜잭션을 **일부러 나눠야 하는** 경우다.

## 문제 상황

주문 처리 중 `product_stat`의 판매 통계를 갱신하는 부가 로직이 함께 실행되고 있었다.
기존에는 메인 비즈니스 로직과 같은 트랜잭션에서 실행했기 때문에, 부가 로직에서 데이터베이스 오류가 발생하면 주문 트랜잭션에도 영향을 줄 수 있었다.

```java
try {
    productStatMapper.increaseSalesCount(...);
} catch (Exception e) {
    log.warn("판매 통계 갱신 실패");
}
```

`try-catch`는 예외 전파를 막아 주지만, 트랜잭션 자체를 분리하지는 않는다.

## 개선 방법

부가 로직을 별도의 Spring Bean으로 분리하고 `REQUIRES_NEW`를 적용했다.
호출부에서는 `try-catch`를 유지해 부가 로직의 예외가 메인 비즈니스 로직으로 전파되지 않도록 했다.

```java
try {
    salesStatSideEffect.increaseSalesCount(...);
} catch (Exception e) {
    log.warn("판매 통계 갱신 실패");
}
```

별도 Spring Bean의 메서드에는 `REQUIRES_NEW`를 적용해 독립된 트랜잭션으로 실행했다.

```java
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void increaseSalesCount(...) {
    productStatMapper.increaseSalesCount(...);
}
```

`REQUIRES_NEW`가 적용되면 기존 트랜잭션은 잠시 중단되고, 판매 통계 갱신을 위한 새로운 트랜잭션이 시작된다.

- 업데이트 성공: 신규 트랜잭션만 별도로 커밋
- 업데이트 실패: 신규 트랜잭션만 롤백
- 호출부의 `try-catch`: 예외가 메인 로직으로 전파되는 것을 차단

## 처리 흐름

```text
주문 트랜잭션
├─ 메인 비즈니스 로직 실행
├─ 판매 통계 신규 트랜잭션 실행
│  ├─ 성공 → 별도 커밋
│  └─ 실패 → 해당 트랜잭션만 롤백
└─ 주문 로직 계속 진행 및 커밋
```

## 정리

- `try-catch`는 예외 전파를 제어한다.
- `REQUIRES_NEW`는 트랜잭션과 롤백 범위를 분리한다.
- 부가 로직의 실패가 핵심 로직에 영향을 주면 안 될 때 활용할 수 있다.
- 트랜잭션 프록시가 적용되도록 별도의 Spring Bean을 통해 호출해야 한다.
- `REQUIRES_NEW`는 새 트랜잭션을 새 커넥션에서 시작한다. `set_config(..., true)`로 건 `search_path`는 이어지지 않으므로, 새 트랜잭션에서도 테넌트 스키마가 다시 적용되는지 확인해야 한다.

> 신규 트랜잭션이 먼저 커밋된 후 메인 로직이 실패하면, 메인 트랜잭션만 롤백되고 판매 통계 변경 사항은 유지된다.
{: .prompt-warning }
