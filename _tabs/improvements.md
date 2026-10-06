---
# 스타일은 _sass/custom/_troubleshooting.scss 의 ts-* 클래스를 함께 사용합니다.
layout: page
title: 기술 개선 및 정량 성과
icon: fas fa-arrow-trend-up
order: 4
---

<nav class="ts-index" aria-label="사례 목록">
  <a class="ts-index-item" href="#common-library">
    <span class="ts-index-no">01</span>
    <span class="ts-index-title">공통 로직 모듈화</span>
  </a>
  <a class="ts-index-item" href="#notification-partitioning">
    <span class="ts-index-no">02</span>
    <span class="ts-index-title">알림 이력 파티셔닝.</span>
  </a>
  <a class="ts-index-item" href="#single-datasource">
    <span class="ts-index-no">03</span>
    <span class="ts-index-title">멀티테넌시 DataSource 단일화</span>
  </a>
</nav>

<section class="ts-case" id="common-library" markdown="1">

<header class="ts-case-head">
  <span class="ts-case-no">01</span>
  <div>
    <h2 class="ts-case-title">공통 로직 모듈화</h2>
  </div>
</header>

<div class="ts-shots ts-shots-wide" markdown="1">

![공통 로직 모듈화](/assets/img/troubleshooting/docker-log-1.png){: w="1600" h="815" }

</div>

<div class="ts-block ts-issue" markdown="1">

### 배경

- 6개 마이크로서비스에 검증, 예외/에러코드, 인증 헬퍼, DTO 변환 등 공통 비즈니스 로직이 각각 복사되어 존재.
- 동일 로직 수정 시마다 서비스별 PR·리뷰·배포가 반복되어 반영 범위가 넓고 버전 불일치 리스크 상존.

</div>

<div class="ts-block ts-fix" markdown="1">

### 목표

- 중복 구현된 공통 로직을 Maven 외부 라이브러리 1종으로 통합.
- GitLab Package Registry로 패키지 버전 및 의존성을 중앙에서 일괄 관리.
- 공통 로직 변경 시 반영 범위를 라이브러리 단위로 축소.

</div>

<div class="ts-block ts-cause" markdown="1">

### LOC 측정 방법

3개 서비스에서 공통 모듈 추출 시 제거된 Java 코드를 부모 커밋 기준으로 복원하고, 공통 라이브러리와 동일한 LOC 산정 기준을 적용해 분리 전·후 코드량을 비교.

- 공통 라이브러리를 사용하는 3개 마이크로서비스를 대상으로 공통 모듈 추출 전·후의 Java 코드량을 비교.
- 각 서비스의 Git 이력에서 공통 모듈 분리 / 공통 모듈 변경 커밋을 확인하고, 해당 커밋에서 삭제된 `.java` 파일을 `git diff-tree --diff-filter=D`로 추출.
- **Before:** 삭제된 각 파일을 부모 커밋 기준 `git show <부모>:<경로>`로 복원한 뒤, 동일한 PowerShell 스크립트로 LOC 집계.
  - 빈 줄·라인 주석·블록 주석 제외
  - 테스트·리소스·비 Java 파일 제외
  - 3개 서비스에서 제거된 코드를 서비스별 중복을 포함한 상태로 합산
- **After:** 공통 라이브러리의 `src/main/java` 하위 `.java` 파일을 동일 스크립트·동일 기준으로 집계.
- Before와 After의 LOC 차이를 기준으로 공통 코드 통합에 따른 중복 코드 감소율을 산출.

</div>

<div class="ts-block ts-verify" markdown="1">

### 측정 결과

3개 마이크로서비스에 중복되어 있던 공통 Java 코드를 외부 라이브러리로 통합해 1,252 LOC → 769 LOC로 약 39%(483 LOC) 축소하고, 서비스별로 분산되어 있던 공통 로직의 변경 지점을 단일 라이브러리로 일원화.

<div class="ts-compare" markdown="1">

| 지표 | Before | After |
| --- | --- | --- |
| 3개 서비스 공통 코드 합계 | 1,252 LOC | 769 LOC (−39%) |
| 공통 로직 수정 시 | 3개 서비스 개별 변경 | 공통 라이브러리 1곳 변경 구조로 전환 |

</div>

- 공통 라이브러리 전환으로 483 LOC 감소.
- 서비스별로 중복 관리하던 코드를 단일 공통 라이브러리로 통합.
- LOC 기준 중복 코드량을 약 39% 축소하면서 공통 기능의 변경 지점을 단일화.

</div>

</section>

<section class="ts-case" id="notification-partitioning" markdown="1">

<header class="ts-case-head">
  <span class="ts-case-no">02</span>
  <div>
    <h2 class="ts-case-title">알림 이력 파티셔닝.</h2>
  </div>
</header>

<div class="ts-shots ts-shots-wide" markdown="1">

![알림 이력 파티셔닝](/assets/img/troubleshooting/docker-log-1.png){: w="1600" h="815" }

</div>

<div class="ts-block ts-issue" markdown="1">

### 배경

- 알림 발송 대상 이력(`notification_send_target`)이 일자별로 쌓이며, 보관 상한이 없으면 조회 범위·용량이 누적에 비례해 커짐.
- 파티션 생성·삭제를 수동으로 하면 누락 위험이 있고, 이후 사용자·발송량이 늘어도 전표 스캔 구조면 성능이 같이 악화될 수 있음.

</div>

<div class="ts-block ts-fix" markdown="1">

### 목표

- MySQL 월 단위 RANGE 파티셔닝(`sent_at`)으로 조회 범위를 월 단위로 제한.
- Jenkins Pipeline으로 매월 익월 파티션 자동 생성 및 6개월 초과 파티션 자동 삭제로 보관 주기·용량 고정.
- 전표 스캔 부담을 줄여 데이터 증가와 무관하게 조회 성능이 유지되는 운영 구조 확보.

</div>

<div class="ts-block ts-cause" markdown="1">

### 성능 지표 측정 방법

24개월·6개월 분량을 단기간 적재해 비파티션 vs 월 파티션(6개월 보관)을 실측. 용량·목록 P95·EXPLAIN·삭제(DELETE vs DROP)를 동일 조건으로 비교.

- 운영 서버와 동일한 호스트 내 별도 DB에 벤치 테이블 2종 구성.
  - **Before:** 비파티션 + 24개월 분량 더미(일 500행)
  - **After:** `sent_at` 월 RANGE 파티션 + 6개월만 보관.
- 동일 월 구간(2026-08)으로 비교:
  - (1) 알림함형 목록 `ORDER BY sent_at DESC LIMIT 50`
  - (2) 월 집계 `COUNT(*)` → 각각 EXPLAIN·50회 반복 후 P95.
- 용량은 `data_length + index_length`(MB)로 비교.
- 보관 주기 적용 비용은 Before: 6개월 초과 행 DELETE vs After: 월 파티션 DROP 소요 시간으로 비교.

</div>

<div class="ts-block ts-verify" markdown="1">

### 측정 결과

알림 발송 대상 이력을 월 파티션·6개월 보관으로 전환해 용량을 124→34 MB(−73%)로 줄이고 월 목록 조회 P95를 495→86 ms(−83%) 단축<br>오래된 데이터 제거도 DELETE 대비 DROP이 약 48% 빠름.

<div class="ts-compare" markdown="1">

| 지표 | Before | After |
| --- | --- | --- |
| 정상 상태 용량 | ≈ 124 MB | 34 MB (−73%), 보관 6개월 고정 |
| 알림함 월 범위 목록 조회 P95 | 495 ms | 86 ms (−83%) |
| 월 조회 EXPLAIN 추정 rows | ≈ 31,000 | 7,600 (−76%) |
| 보관 주기 적용 | 행 DELETE ≈ 3.7 s | 월 파티션 DROP ≈ 1.9 s (−48%) |
| 파티션 운영 | 월 수동 ≈ 0.5 MD | Pipeline 자동화 |

</div>

- **가정·적재:** 일 500행 → 월 약 15,000행 / 24개월 누적 vs 6개월 보관

</div>

</section>

<section class="ts-case" id="single-datasource" markdown="1">

<header class="ts-case-head">
  <span class="ts-case-no">03</span>
  <div>
    <h2 class="ts-case-title">멀티테넌시 DataSource 단일화</h2>
  </div>
</header>

<div class="ts-shots ts-shots-wide" markdown="1">

![멀티테넌시 DataSource 단일화](/assets/img/troubleshooting/docker-log-1.png){: w="1600" h="815" }

</div>

<div class="ts-block ts-issue" markdown="1">

### 배경

- MySQL 기반 서비스를 운영하며 테넌트별로 DataSource·커넥션 풀을 두던 구조에서는, 테넌트 수 `N`에 비례해 풀·설정·모니터링 포인트가 함께 증가함.
- 테넌트가 수십~수백으로 늘면 DB 커넥션·메모리·Spring 다중 DataSource 구성이 동시에 커지고, 장애 대응·튜닝 지점도 `N`개로 분산됨.
- 데이터 격리는 필요하지만, 테넌트당 풀을 유지하면 확장 시 자원·운영 비용이 선형으로 악화되는 구조.

</div>

<div class="ts-block ts-fix" markdown="1">

### 목표

- PostgreSQL 스키마 단위 멀티 테넌시로 테넌트별 데이터를 논리 격리.
- 단일 DataSource + 요청 단위 `SET search_path` 로 테넌트를 전환해, 수십~수백 테넌트를 공유 커넥션 풀 1개에서 처리.
- DataSource 다중 구성을 제거해 Spring 설정·커넥션 모니터링 포인트를 1개로 단순화하고, 테넌트 증가와 무관하게 풀·설정 규모가 고정되는 운영 구조 확보.

</div>

<div class="ts-block ts-cause" markdown="1">

### 성능 지표 측정 방법

100개 테넌트 동일 CRUD workload로 테넌트별 pool vs 단일 shared pool을 실측. pool 구성 규모·응답시간·처리량·실패율을 동일 조건으로 비교.

- 동일 PostgreSQL·동일 schema/seed로 두 구조를 비교.
  - **Before:** 테넌트별 HikariCP DataSource/pool
  - **After:** DataSource 1개 + 공유 HikariCP pool 1개
- 조건 고정: 테넌트 100, pool size 10.
- schema 전환:
  - Before는 pool `connectionInitSql`로 `search_path` 고정
  - After는 요청 transaction마다 `set_config('search_path', ?, true)`
- 동일 Locust 부하 15분: 100 users, ramp 20/s, 목록 70%·단건 20%·생성 10%, tenant uniform.
- 측정: Locust stats·stats_history(요청·실패·평균·p95·p99·RPS) + Prometheus/Grafana·postgres-exporter.

</div>

<div class="ts-block ts-verify" markdown="1">

### 측정 결과

테넌트별 HikariCP pool 구조를 PostgreSQL schema 기반 단일 shared pool로 전환<br>configured pool 수를 100개에서 1개로, connection capacity를 약 1,000개에서 10개로 각각 99% 줄였다.<br>동일한 혼합 CRUD 부하에서 p95·p99 응답시간은 각각 2ms·4ms로 동일하게 관측됐고 두 실행 모두 실패율 0% 기록

<div class="ts-compare" markdown="1">

| 지표 | Before | After |
| --- | --- | --- |
| configured pool 수 | 100 | 1 (−99%) |
| configured connection capacity | ≈ 1,000 | 10 (−99%) |
| pool metric series | 100 | 1 |
| aggregate 실패 | 0 | 0 |
| p95/p99 | 2ms / 4ms | 동일 |
| 평균 응답시간 | 1.1354 | 1.1387 ms (+0.29%) |
| 100 users 평균 RPS | 1,927.8 | 1,931.4 req/s (+0.19%) |

</div>

- **조건:** 테넌트 100 / pool size 10 / Locust 100 users / 15분

</div>

</section>
