---
title: REQUIRES_NEW를 활용한 부가 로직 트랜잭션 분리 처리
date: 2026-07-25 23:00:00 +0900
categories: [Spring, Transaction]
tags: [spring, transaction, propagation, requires-new]
---

## 문제 상황

창고 이동 처리 중 `item_lot`의 사용 여부를 변경하는 부가 로직이 함께 실행되고 있었다.
기존에는 메인 비즈니스 로직과 같은 트랜잭션에서 실행했기 때문에, 부가 로직에서 데이터베이스 오류가 발생하면 창고 이동 트랜잭션에도 영향을 줄 수 있었다.

```java
try {
    itemLotMapper.updateUseYnByItemAndLot(...);
} catch (Exception e) {
    log.warn("item_lot 업데이트 실패");
}
```

`try-catch`는 예외 전파를 막아 주지만, 트랜잭션 자체를 분리하지는 않는다.

## 개선 방법

부가 로직을 별도의 Spring Bean으로 분리하고 `REQUIRES_NEW`를 적용했다.
호출부에서는 `try-catch`를 유지해 부가 로직의 예외가 메인 비즈니스 로직으로 전파되지 않도록 했다.

```java
try {
    lotUsageSideEffect.markLotUsed(...);
} catch (Exception e) {
    log.warn("item_lot 업데이트 실패");
}
```

별도 Spring Bean의 메서드에는 `REQUIRES_NEW`를 적용해 독립된 트랜잭션으로 실행했다.

```java
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void markLotUsed(...) {
    itemLotMapper.updateUseYnByItemAndLot(...);
}
```

`REQUIRES_NEW`가 적용되면 기존 트랜잭션은 잠시 중단되고, `item_lot` 업데이트를 위한 새로운 트랜잭션이 시작된다.

- 업데이트 성공: 신규 트랜잭션만 별도로 커밋
- 업데이트 실패: 신규 트랜잭션만 롤백
- 호출부의 `try-catch`: 예외가 메인 로직으로 전파되는 것을 차단

## 처리 흐름

```text
창고 이동 트랜잭션
├─ 메인 비즈니스 로직 실행
├─ item_lot 신규 트랜잭션 실행
│  ├─ 성공 → 별도 커밋
│  └─ 실패 → 해당 트랜잭션만 롤백
└─ 창고 이동 로직 계속 진행 및 커밋
```

## 정리

- `try-catch`는 예외 전파를 제어한다.
- `REQUIRES_NEW`는 트랜잭션과 롤백 범위를 분리한다.
- 부가 로직의 실패가 핵심 로직에 영향을 주면 안 될 때 활용할 수 있다.
- 트랜잭션 프록시가 적용되도록 별도의 Spring Bean을 통해 호출해야 한다.

> 신규 트랜잭션이 먼저 커밋된 후 메인 로직이 실패하면, 메인 트랜잭션만 롤백되고 `item_lot` 변경 사항은 유지된다.
{: .prompt-warning }
