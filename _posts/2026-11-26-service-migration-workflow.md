---
title: "AI로 서비스 이관하기 (1) - 단독형 MES를 SaaS로 옮기다"
description: "단독형 MES의 운영 MySQL에서 SaaS의 로컬 PostgreSQL로 데이터를 옮긴 과정. AI 에이전트로 업무를 비교하고, 매핑·적재한 뒤 원본과 대조했다."
date: 2026-11-26 09:00:00 +0900
categories: [AI 활용, 서비스 이관]
tags: [migration, multi-tenant, ai-agent, postgresql]
---

<link rel="stylesheet" href="{{ '/assets/css/fmes-migration.css' | relative_url }}">

A는 한 고객사가 단독으로 쓰던 MES(MySQL), B는 여러 고객사가 함께 쓰는 SaaS(PostgreSQL)다. 이관할 때는 과거 주문·배송을 조회할 수 있게 보관하고, 진행 중인 건은 B에서 다음 작업을 이어갈 수 있도록 연결해야 했다.

## A에서 B로 데이터를 옮긴 경로

<figure class="fmes-case-flow">
  <ol class="fmes-case-stages" aria-label="추출부터 적재까지">
    <li><strong>A · 운영 MySQL</strong><span>대상 고객사 데이터만 읽기 전용으로 추출</span></li>
    <li><strong>PostgreSQL 임시 테이블</strong><span>원본을 복사하고 적재 전 건수 확인</span></li>
    <li><strong>변환 SQL</strong><span>코드값 변환과 기존 ID·신규 ID 대응표 생성</span></li>
  </ol>
  <div class="fmes-case-target">
    <p class="fmes-case-target-label">B · 로컬 PostgreSQL의 고객사 전용 영역</p>
    <div class="fmes-case-paths">
      <div><strong>이력 보관</strong><span>주문·출하·배송 이력을 보관 테이블에 적재</span></div>
      <div><strong>업무를 이어갈 데이터</strong><span>기준정보 → 진행 중 주문 → 배송 배정 순서로 연결</span></div>
    </div>
  </div>
  <figcaption>배송 상세를 연결하려면 새 주문 상세 ID가 필요하다. 주문 역시 먼저 적재된 상품·거래처를 참조한다.</figcaption>
</figure>

## AI 에이전트가 분석에서 검증까지 진행한 방식

<dl class="fmes-case-decisions">
  <div><dt>업무 흐름 비교</dt><dd>A의 화면에서 API와 테이블을 따라가며 B의 대응 기능을 찾았다. B의 표준 기능과 설정을 우선 활용하고, 차이가 남는 부분은 고객사 전용 기능으로 설계했다.</dd></div>
  <div><dt>데이터 매핑과 적재</dt><dd>A의 값이 B의 어느 컬럼으로 가는지 정리하고, 매핑표를 바탕으로 추출·변환·적재 SQL을 작성했다. 운영 MySQL은 조회만 했고 승인된 로컬 PostgreSQL에서 적재를 실행했다.</dd></div>
  <div><dt>독립 검증</dt><dd>처음 매핑을 작성한 맥락을 공유하지 않은 별도 에이전트가 원본과 적재 결과를 다시 비교했다. 테이블별 건수와 금액·수량 집계, 주문과 배송의 참조 관계를 확인했다.</dd></div>
</dl>

## 진행 중 주문에 판매가가 연결되도록 했다

<dl class="fmes-case-decisions">
  <div><dt>발견한 문제</dt><dd>새 SaaS는 주문일 기준으로 판매가를 찾는다. 기존 주문일이 이관 판매가의 효력 시작일보다 앞서면 단가를 찾을 수 없었다.</dd></div>
  <div><dt>적용한 규칙</dt><dd>새 업무 테이블에는 주문일과 전환 기준일 중 늦은 날짜를 쓰고, 원래 주문일은 확장 테이블에 보존했다.</dd></div>
  <div><dt>로컬 대사 결과</dt><dd>확정에 필요한 판매가가 없는 주문 <strong>0건</strong>. 배송 상세가 가리키는 주문 상세의 누락도 <strong>0건</strong>이었다.</dd></div>
</dl>

## 같은 스냅샷으로 다시 실행할 수 있게 했다

같은 입력을 넣으면 이미 적재한 행을 건너뛰게 했다. 변환 규칙을 수정할 때는 이관 표시와 ID 대응표로 해당 행을 찾아 지운 뒤 다시 적재할 수 있게 했다. 기준정보와 진행 중인 건은 Flyway 파일로 만들고, 대용량 보관 이력은 별도 적재 스크립트로 남겼다.

## 로컬 리허설 결과

같은 스냅샷을 기준으로 A와 B를 대조했다. 보관 이력은 테이블별 건수를 비교하고, 진행 중 주문과 배송 배정은 상세 행과 참조 관계까지 확인했다.

<section class="fmes-case-hero" aria-label="로컬 리허설 결과">
  <dl class="fmes-case-metrics" aria-label="로컬 리허설 대사 결과">
    <div><dt>보관 이력</dt><dd><strong>369,696</strong>행</dd><dd>7개 테이블별 건수 일치</dd></div>
    <div><dt>진행 중 주문</dt><dd><strong>161</strong>건</dd><dd>상세 219행</dd></div>
    <div><dt>진행 중 배송 배정</dt><dd><strong>111</strong>건</dd><dd>상세 168행</dd></div>
  </dl>
  <p class="fmes-case-state"><strong>로컬 리허설에서 적재·대사 완료</strong><span>업무 시나리오 실측과 운영 전환은 후속 작업</span></p>
</section>

운영 전환 계획에는 전용 기능을 적용한 뒤 주문 확정·배송 배정·취소를 실측하고, A의 입력을 동결한 시점의 데이터로 최종 적재와 대사를 다시 실행하는 절차를 담았다.

## 실행 기록

- [추출·변환·적재 SQL과 재실행 방식]({{ '/posts/service-migration-data-mapping/' | relative_url }})
- [원본 대사 결과와 운영 전환 절차]({{ '/posts/service-migration-verification/' | relative_url }})
