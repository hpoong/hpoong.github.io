---
title: AI로 DB 튜닝하기 (1) - pg_stat_statements로 튜닝 대상 찾기
date: 2026-10-29 09:00:00 +0900
categories: [AI 활용, DB 성능 최적화]
tags: [postgresql, pg-stat-statements, performance, query-tuning]
---

## 왜 필요한가

쿼리 튜닝은 보통 "느리다"는 제보에서 시작한다. 제보가 들어온 화면의 쿼리를 찾아 `EXPLAIN`을 돌리고 고친다.

이 방식은 **눈에 띈 쿼리만** 고친다는 한계가 있다.

- 한 번에 0.05초씩 걸려도 하루에 수십만 번 호출되면 DB 전체 시간의 대부분을 차지할 수 있다.
- 사용자가 직접 보지 않는 배치나 내부 API의 쿼리는 제보 자체가 없다.
- 고친 뒤에 DB 전체 부하가 실제로 줄었는지 확인할 기준이 없다.

튜닝 대상을 고르려면 **어떤 쿼리가 DB 시간을 얼마나 쓰고 있는지** 전체 통계가 필요하다.

AI 에이전트에게 튜닝을 맡길 때도 마찬가지다. 에이전트는 소스는 잘 읽지만 DB에서 실제로 어떤 쿼리가 무거운지는 모른다. 이 통계가 있어야 에이전트가 **추측이 아니라 근거를 보고** 튜닝 대상을 고를 수 있다.

## pg_stat_statements란

`pg_stat_statements`는 PostgreSQL에 포함된 확장 기능이다. 서버에서 실행된 SQL을 **같은 모양끼리 묶어** 호출 횟수, 실행 시간, 읽은 블록 수 등을 누적한다.

"같은 모양"은 상수만 다른 쿼리를 말한다. 아래 두 쿼리는 하나의 항목으로 집계된다.

```sql
SELECT * FROM work_order WHERE order_no = 'WO-001';
SELECT * FROM work_order WHERE order_no = 'WO-002';
```

```sql
-- pg_stat_statements에 저장되는 형태
SELECT * FROM work_order WHERE order_no = $1
```

항목은 `queryid`로 구분한다. `queryid`는 SQL 문자열이 아니라 **파싱 결과**로 계산되므로, 공백이나 주석이 달라도 같은 쿼리로 묶인다.

## 활성화하기

### 1. 서버 시작 시 로드한다

`pg_stat_statements`는 공유 메모리를 쓰기 때문에 **서버 시작 시점에 로드**해야 한다. `postgresql.conf`에 추가하고 PostgreSQL을 재시작한다.

```conf
shared_preload_libraries = 'pg_stat_statements'
```

Docker로 띄운 PostgreSQL이라면 실행 옵션으로 넘길 수 있다.

```yaml
services:
  postgres:
    image: postgres:17
    command: postgres -c shared_preload_libraries=pg_stat_statements
```

관리형 DB(RDS 등)는 파라미터 그룹에서 같은 값을 설정한다.

### 2. 조회할 DB에 확장을 만든다

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

통계 수집은 1번 설정만으로 **서버 전체**에서 이뤄진다. `CREATE EXTENSION`은 그 통계를 조회할 뷰와 함수를 만드는 단계라서, 조회에 쓸 DB 한 곳에만 만들면 된다.

### 3. 적용 여부를 확인한다

```sql
SHOW shared_preload_libraries;
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';
```

### 주요 설정

| 설정 | 기본값 | 의미 |
| --- | --- | --- |
| `pg_stat_statements.max` | 5000 | 보관할 최대 항목 수. 넘치면 적게 실행된 항목부터 버린다. |
| `pg_stat_statements.track` | `top` | `top`은 클라이언트가 보낸 쿼리만, `all`은 함수 안에서 실행된 쿼리까지 집계 |
| `pg_stat_statements.track_utility` | `on` | `SELECT`/`INSERT` 등이 아닌 명령(`SET`, `VACUUM` 등)도 집계 |
| `pg_stat_statements.save` | `on` | 정상 종료 시 통계를 파일로 저장해 재시작 후에도 유지 |

## 조회 권한

뷰 자체는 누구나 조회할 수 있지만, **다른 사용자가 실행한 쿼리의 SQL 문자열**은 권한이 없으면 `<insufficient privilege>`로 가려진다.

분석용 계정에는 통계 조회 권한만 준다.

```sql
GRANT pg_read_all_stats TO analyst;
```

`pg_monitor` 역할은 `pg_read_all_stats`에 설정 조회 등을 더한 모니터링용 묶음이다. 분석 도구가 요구하면 `pg_monitor`를 준다.

## 주요 컬럼

PostgreSQL 13부터 실행 시간 컬럼 이름이 `total_time`에서 `total_exec_time`으로 바뀌었다. 아래는 13 이상 기준이다.

| 컬럼 | 의미 | 볼 때 |
| --- | --- | --- |
| `calls` | 실행 횟수 | 자주 불리는 쿼리 |
| `total_exec_time` | 누적 실행 시간(ms) | **DB 전체 부하에 기여한 정도** |
| `mean_exec_time` | 평균 실행 시간(ms) | 한 번 실행할 때 느린 쿼리 |
| `max_exec_time` | 최대 실행 시간(ms) | 가끔 튀는 쿼리 |
| `rows` | 누적 반환/처리 행 수 | `rows / calls`로 1회당 행 수 |
| `shared_blks_hit` | 캐시에서 읽은 블록 수 | 캐시 적중률 |
| `shared_blks_read` | 디스크에서 읽은 블록 수 | 디스크 I/O가 많은 쿼리 |
| `temp_blks_written` | 임시 파일에 쓴 블록 수 | 정렬·해시가 메모리를 넘친 쿼리 |

## 부하가 큰 쿼리 찾기

### 누적 실행 시간 상위

튜닝 효과가 가장 큰 쿼리부터 찾는다. `pct`는 전체 실행 시간 중 해당 쿼리가 차지하는 비율이다.

```sql
SELECT queryid,
       calls,
       round(total_exec_time::numeric, 1)                                AS total_ms,
       round(mean_exec_time::numeric, 2)                                 AS mean_ms,
       round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 1) AS pct,
       rows / NULLIF(calls, 0)                                           AS rows_per_call,
       left(query, 100)                                                  AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 20;
```

뷰에는 서버의 모든 DB 통계가 섞여 있으므로 `dbid`로 현재 DB만 걸러낸다.

### 평균 실행 시간 상위

한 번 실행할 때 느린 쿼리를 찾는다. 몇 번 안 불린 관리용 쿼리가 섞이지 않도록 호출 횟수 조건을 둔다.

```sql
SELECT queryid,
       calls,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       round(max_exec_time::numeric, 2)  AS max_ms,
       left(query, 100)                  AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND calls >= 50
ORDER BY mean_exec_time DESC
LIMIT 20;
```

### 디스크 I/O와 임시 파일

캐시 적중률이 낮거나 임시 파일을 쓰는 쿼리를 찾는다.

```sql
SELECT queryid,
       calls,
       shared_blks_read,
       round(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 1) AS hit_pct,
       temp_blks_written,
       left(query, 100) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY shared_blks_read DESC
LIMIT 20;
```

## 결과 읽는 법

| 패턴 | 의심할 점 |
| --- | --- |
| `total_exec_time` 상위, `mean_exec_time`은 작음 | 쿼리 자체보다 **호출 횟수**가 문제. 반복 호출(N+1)이나 캐시 가능 여부를 본다. |
| `mean_exec_time`이 큼 | 실행 계획 문제. 인덱스 누락, 잘못된 조인 순서를 `EXPLAIN`으로 확인한다. |
| `mean`은 작은데 `max`가 큼 | 특정 파라미터 값이나 락 대기에서만 느려진다. |
| `rows_per_call`이 큼 | 필요 이상으로 많은 행을 가져온다. 페이징이나 조건을 확인한다. |
| `hit_pct`가 낮음 | 디스크에서 많이 읽는다. 큰 테이블을 넓게 스캔하는지 본다. |
| `temp_blks_written` > 0 | 정렬·해시가 `work_mem`을 넘쳐 디스크를 쓴다. |

## 측정 구간 정하기

통계는 **마지막 초기화 이후 누적값**이다. 언제부터 쌓였는지 모르면 튜닝 전후를 비교할 수 없다.

```sql
SELECT pg_stat_statements_reset();
```

초기화 → 일정 기간 운영 또는 부하 테스트 → 조회 순서로 구간을 잡는다. 튜닝 후 같은 방식으로 다시 측정해 `total_exec_time`과 `mean_exec_time`을 비교한다.

`pg_stat_statements_reset()`은 기본적으로 슈퍼유저만 실행할 수 있다. PostgreSQL 17부터는 항목별로 집계 시작 시각(`stats_since`)을 볼 수 있다.

## 소스와 연결하기

`pg_stat_statements`가 알려주는 것은 정규화된 SQL 문자열까지다. 이 쿼리가 **애플리케이션의 어느 코드에서** 나왔는지는 직접 찾아야 한다.

MyBatis 매퍼라면 쿼리에 매퍼 ID를 주석으로 남겨 두면 추적이 쉽다. `queryid`는 주석을 무시하지만, 저장되는 SQL 문자열에는 주석이 그대로 남는다.

```xml
<select id="selectWorkOrderList" resultType="WorkOrder">
    /* WorkOrderMapper.selectWorkOrderList */
    SELECT ...
</select>
```

## 한계

- **실제 파라미터 값이 없다.** 상수가 `$1`로 바뀌므로, `EXPLAIN`으로 재현할 때는 대표 값을 직접 넣어야 한다.
- **실행 계획이 없다.** 느린 이유는 `EXPLAIN (ANALYZE, BUFFERS)`로 따로 확인한다.
- **시간대별 변화가 없다.** 누적값이라 "언제 느려졌는지"는 알 수 없다. 주기적으로 스냅샷을 떠서 차이를 봐야 한다.
- **PostgreSQL 17 이하에서는 `IN` 목록 길이가 다르면 다른 쿼리로 잡힌다.** MyBatis `<foreach>`로 만든 `IN (...)`은 원소 개수마다 항목이 나뉘어 통계가 흩어진다. 18부터는 상수 목록이 하나로 묶인다.
- **항목 수에 상한이 있다.** `pg_stat_statements.max`를 넘으면 오래된 항목이 버려진다.

## 정리

- `pg_stat_statements`는 상수만 다른 쿼리를 묶어 **호출 횟수와 실행 시간을 누적**한다.
- 활성화에는 `shared_preload_libraries` 설정과 **재시작**, 그리고 `CREATE EXTENSION`이 필요하다.
- 분석 계정에는 `pg_read_all_stats`(또는 `pg_monitor`)를 줘야 다른 사용자의 SQL 문자열이 보인다.
- 튜닝 대상은 **`total_exec_time` 상위**부터 고른다. 개별 느린 쿼리는 `mean_exec_time`으로 따로 본다.
- 통계는 누적값이므로 **초기화 시점을 정해** 튜닝 전후를 비교한다.

> `shared_preload_libraries` 변경은 PostgreSQL 재시작이 필요하다. 운영 DB라면 점검 시간에 적용한다.
{: .prompt-warning }

> 정규화된 SQL에도 테이블명, 컬럼명 등 스키마 정보가 그대로 남는다. 조회 결과를 외부 도구나 채팅에 붙일 때는 노출 범위를 확인한다.
{: .prompt-tip }

이 통계를 에이전트에 연결하는 방법은 [AI로 DB 튜닝하기 (2) - pgAssistant를 에이전트에 연결하기](/posts/pgassistant-local-setup/)에 정리했다.

## 참고

- [PostgreSQL 문서: pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html)
