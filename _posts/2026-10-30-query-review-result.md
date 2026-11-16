---
title: AI로 DB 튜닝하기 (3) - 에이전트가 찾은 쿼리 문제 5가지
date: 2026-10-30 09:00:00 +0900
categories: [AI, DB 튜닝]
tags: [ai-agent, postgresql, mybatis, query-tuning, explain]
---

[(2)편](/posts/pgassistant-local-setup/)에서 pgAssistant와 PostgreSQL MCP를 에이전트에 연결했다. 이번에는 그 에이전트에게 MES 매퍼의 SELECT 전체를 점검시킨 결과를 정리한다. 확정 기준을 모두 통과한 **5건**을 다룬다.

<div class="qr-hero">
  <span class="qr-hero-tag">query-review · 점검 결과</span>
  <div class="qr-hero-title">SELECT 1,695개 점검, <em>확정 5건</em></div>
  <p class="qr-hero-desc">매퍼의 SELECT 전체를 스키마와 대조하고, 운영기에서 이관한 데이터가 있는 개발 DB에서 직접 실행해 쟀다. 실행 시 오류, 지워도 되는 조인, 재작성 대상을 찾고 확정 기준을 모두 통과한 항목만 남겼다.</p>
  <div class="qr-hero-meta">
    <div>대상<b>MES 코어 · 인증 서비스</b></div>
    <div>범위<b>매퍼 도메인 25개</b></div>
    <div>DB<b>개발 PostgreSQL · 운영 데이터 이관</b></div>
    <div>점검일<b>2026-10-30</b></div>
  </div>
</div>

<div class="qr-kpis">
  <div class="qr-kpi"><div class="qr-kpi-label">코드 점검</div><div class="qr-kpi-value">1,695</div><div class="qr-kpi-note">SELECT 전체 · 스키마와 대조</div></div>
  <div class="qr-kpi"><div class="qr-kpi-label">실행 측정</div><div class="qr-kpi-value">453<small>건</small></div><div class="qr-kpi-note">1,695개 중 1,000건 이상 테이블을 쓰는 쿼리</div></div>
  <div class="qr-kpi is-hl"><div class="qr-kpi-label">확정 항목</div><div class="qr-kpi-value">5<small>건</small></div><div class="qr-kpi-note">오류 2 · 재작성 1 · 조인 2</div></div>
  <div class="qr-kpi"><div class="qr-kpi-label">최대 개선</div><div class="qr-kpi-value">-62<small>%</small></div><div class="qr-kpi-note">조인 삭제 · 결과 동일</div></div>
</div>

## 결론

먼저 고칠 것은 **실행하면 오류가 나는 쿼리**다. 서비스 오픈 전이라 데이터가 많지 않아(가장 큰 테이블이 7,586건) 인덱스로 확정할 항목은 없었다. 성능 개선이 수치로 확인된 것은 1건뿐이고, 나머지는 스키마와 맞지 않는 쿼리와 지워도 결과가 같은 조인이다.

<div class="qr-verdicts">
  <div class="qr-vbox is-error">
    <div class="qr-vbox-head"><b>2</b> 실행 시 SQL 오류</div>
    <p>없는 컬럼 1건, 선언되지 않은 별칭 1건. 두 건 모두 분기 조건과 관계없이 항상 오류가 난다.</p>
  </div>
  <div class="qr-vbox is-join">
    <div class="qr-vbox-head"><b>2</b> 지워도 되는 조인</div>
    <p>ON 밖에서 쓰지 않고 ON 조건이 PK·UNIQUE를 모두 덮는 LEFT JOIN. 1건은 공유 SQL 조각 안에 있어 조각을 나눠야 한다.</p>
  </div>
  <div class="qr-vbox is-rewrite">
    <div class="qr-vbox-head"><b>1</b> 재작성 (성능)</div>
    <p>조건이 잘못 걸린 조인 하나를 지워 쿼리 2개가 42~62% 빨라졌다. 결과는 같다.</p>
  </div>
  <div class="qr-vbox">
    <div class="qr-vbox-head"><b>0</b> 인덱스</div>
    <p>인덱스 확정 기준(테이블 1만 건 이상)을 만족하는 테이블이 아직 없다. 오픈 후 다시 측정한다.</p>
  </div>
</div>

## 문제 5건

카드를 누르면 펼쳐진다. 각 카드는 현재 코드, 근거, 영향, 수정안 순서로 정리했다.

<details class="qr-card is-error" id="qr-01" markdown="1">
<summary markdown="0">
  <div class="qr-card-head"><span class="qr-card-no">01</span><span class="qr-card-title">사용자 상세 조회가 users에 없는 DEPT_CODE로 거른다</span><span class="qr-card-toggle"></span></div>
  <div class="qr-pills"><span class="qr-pill is-error">존재하지 않는 컬럼</span><span class="qr-pill is-muted">사용자</span><span class="qr-pill is-rewrite">수정안 있음</span></div>
</summary>
<div class="qr-body" markdown="1">

<span class="qr-k">대상</span> `UserQueryMapper.findUserByDept`

<span class="qr-k">현재 코드</span> `U`는 `USERS`의 별칭이다.

```sql
AND U.DEPT_CODE = #{deptCode}
```

<span class="qr-k">근거</span> Flyway 마이그레이션을 끝까지 적용한 스키마에서 `users`에는 `dept_code`가 없다. 사용자는 부서를 `dept_id`로만 갖고 있고, `dept_code`는 `departments`에만 있다.

<span class="qr-k">영향</span> 분기 조건이 없어 **항상** `column u.dept_code does not exist` 오류가 난다.

<span class="qr-k">수정안</span> 같은 파일의 사용자 목록 조회와 같은 방식으로 부서 테이블을 붙여서 거른다.

```sql
FROM USERS U
INNER JOIN DEPARTMENTS D
        ON D.DEPT_ID   = U.DEPT_ID
       AND D.DEPT_CODE = #{deptCode}
WHERE U.USER_ID = #{userId}
```

</div>
</details>

<details class="qr-card is-error" id="qr-02" markdown="1">
<summary markdown="0">
  <div class="qr-card-head"><span class="qr-card-no">02</span><span class="qr-card-title">작업지시 목록의 바깥 WHERE가 CTE 안의 별칭 wo를 참조한다</span><span class="qr-card-toggle"></span></div>
  <div class="qr-pills"><span class="qr-pill is-error">정의되지 않은 별칭</span><span class="qr-pill is-muted">생산</span><span class="qr-pill is-rewrite">수정안 있음</span></div>
</summary>
<div class="qr-body" markdown="1">

<span class="qr-k">대상</span> `OrderQueryMapper.findOrdersByPeriod`

<span class="qr-k">현재 코드</span>

```xml
with order_list as (
    select ...
    from work_orders wo
    where wo.FACTORY_ID = #{factoryId}
      and wo.STATUS in ('READY', 'RUNNING', 'DONE')
)
select ...
from order_list
<where>
    and wo.FACTORY_ID = #{factoryId}
    <if test="status != null and status != ''">
        and wo.STATUS = #{status}
    </if>
    and wo.START_DATE >= #{dateFrom}::date
    and wo.START_DATE <= #{dateTo}::date
</where>
```

<span class="qr-k">근거</span> 바깥 블록의 FROM에는 CTE `order_list` 하나뿐이다. `wo`는 CTE 본문 안에서만 선언된 별칭이라 바깥에서는 보이지 않는다.

<span class="qr-k">영향</span> 날짜 조건은 분기 없이 들어가므로 **항상** `missing FROM-clause entry for table "wo"` 오류가 난다.

<span class="qr-k">수정안</span> `wo` 조건을 CTE의 WHERE로 옮기고, 바깥에는 CTE가 내보내는 컬럼 조건만 남긴다. 바깥의 `FACTORY_ID` 조건은 CTE 조건과 같아서 뺀다.

```xml
with order_list as (
    select ...
    from work_orders wo
    where wo.FACTORY_ID = #{factoryId}
      and wo.STATUS in ('READY', 'RUNNING', 'DONE')
    <if test="status != null and status != ''">
      and wo.STATUS = #{status}
    </if>
      and wo.START_DATE >= #{dateFrom}::date
      and wo.START_DATE <= #{dateTo}::date
)
select ...
from order_list
<where>
    <if test="orderNo != null and orderNo != ''">
        and order_no like concat(#{orderNo}, '%')
    </if>
</where>
```

</div>
</details>

<details class="qr-card is-rewrite" id="qr-03" markdown="1">
<summary markdown="0">
  <div class="qr-card-head"><span class="qr-card-no">03</span><span class="qr-card-title">재고 조정 이력 조회의 CC2 조인이 자기 별칭을 참조하지 않는다</span><span class="qr-card-toggle"></span></div>
  <div class="qr-pills"><span class="qr-pill is-rewrite">재작성 · 실행 시간 42~62% 감소</span><span class="qr-pill is-muted">재고</span><span class="qr-pill is-rewrite">수정안 있음</span></div>
</summary>
<div class="qr-body" markdown="1">

<span class="qr-k">대상</span> `AdjustmentMapper.findAdjustments`, `AdjustmentMapper.countAdjustments`

<span class="qr-k">현재 코드</span> 두 쿼리에 같은 조인이 있다. `SH`는 `STOCK_HISTORY`의 별칭이다.

```sql
LEFT JOIN COMMON_CODES CC
       ON CC.GROUP_CODE = 'ADJUST_REASON'
      AND CC.CODE = SH.REASON
LEFT JOIN COMMON_CODES CC2
       ON CC.GROUP_CODE = 'ADJUST_STATUS'     -- CC2가 아니라 CC
      AND CC.CODE = SH.REASON
```

<span class="qr-k">근거</span> `CC2`의 ON 조건이 `CC2`를 한 번도 참조하지 않는다. 조인 키가 없으니 PostgreSQL은 행마다 `common_codes` 1,266행을 모두 읽고 Join Filter로 버린다(`Rows Removed by Join Filter: 1266`). 비용은 `stock_history` 결과 행 수에 비례해 늘어난다.

`CC`는 `ADJUST_REASON`일 때만 붙으므로 `CC.GROUP_CODE = 'ADJUST_STATUS'`는 어떤 분기에서도 참이 될 수 없다. `CC2`는 항상 NULL로만 붙고, SELECT와 WHERE 어디에서도 쓰이지 않는다.

<span class="qr-k">수정안</span> 두 쿼리에서 `CC2` 조인을 삭제한다.

<span class="qr-k">실측</span> 캐시가 찬 상태(warm)에서 3회 실행했다. B1은 선택 조건을 모두 뺀 경우, B2는 선택 조건을 넣은 경우다.

<div class="qr-bench">
  <div class="qr-bench-row">
    <span class="qr-bench-label">findAdjustments · B1</span>
    <div class="qr-bench-bars">
      <div class="qr-bar-line"><span style="width:100%"></span><b>0.453</b></div>
      <div class="qr-bar-line is-after"><span style="width:58%"></span><b>0.265</b></div>
    </div>
    <span class="qr-bench-diff">-42%</span>
  </div>
  <div class="qr-bench-row">
    <span class="qr-bench-label">findAdjustments · B2</span>
    <div class="qr-bench-bars">
      <div class="qr-bar-line"><span style="width:98%"></span><b>0.446</b></div>
      <div class="qr-bar-line is-after"><span style="width:47%"></span><b>0.214</b></div>
    </div>
    <span class="qr-bench-diff">-52%</span>
  </div>
  <div class="qr-bench-row">
    <span class="qr-bench-label">countAdjustments · B1</span>
    <div class="qr-bench-bars">
      <div class="qr-bar-line"><span style="width:85%"></span><b>0.383</b></div>
      <div class="qr-bar-line is-after"><span style="width:32%"></span><b>0.145</b></div>
    </div>
    <span class="qr-bench-diff">-62%</span>
  </div>
  <div class="qr-bench-row">
    <span class="qr-bench-label">countAdjustments · B2</span>
    <div class="qr-bench-bars">
      <div class="qr-bar-line"><span style="width:87%"></span><b>0.394</b></div>
      <div class="qr-bar-line is-after"><span style="width:35%"></span><b>0.158</b></div>
    </div>
    <span class="qr-bench-diff">-60%</span>
  </div>
  <div class="qr-bench-legend"><span><i></i>원본 (ms)</span><span><i class="is-after"></i>수정 (ms)</span><span>버퍼 21 → 9 / 19 → 7</span></div>
</div>

<span class="qr-k">결과 동일</span> 원본과 수정본을 같은 바인딩으로 실행해 행 순서까지 비교했다. 차집합은 0건이다.

</div>
</details>

<details class="qr-card is-join" id="qr-04" markdown="1">
<summary markdown="0">
  <div class="qr-card-head"><span class="qr-card-no">04</span><span class="qr-card-title">창고별 재고 건수에서 쓰지 않는 warehouses 조인</span><span class="qr-card-toggle"></span></div>
  <div class="qr-pills"><span class="qr-pill is-join">사용하지 않는 조인</span><span class="qr-pill is-muted">재고</span><span class="qr-pill is-rewrite">수정안 있음</span></div>
</summary>
<div class="qr-body" markdown="1">

<span class="qr-k">대상</span> `StockQueryMapper.countStockByWarehouse`

<span class="qr-k">현재 코드</span> `i`는 `inventory`의 별칭이다.

```sql
LEFT JOIN warehouses w
       ON w.warehouse_id = i.warehouse_id
```

<span class="qr-k">근거</span> 두 조건을 모두 만족해서 지워도 결과가 같다.

- `w`가 자기 ON 밖(COUNT, WHERE, 모든 `<if>` 분기)에서 쓰이지 않는다.
- ON 조건 (`warehouse_id`)이 `warehouses`의 PK를 덮는다. 매칭되는 행이 최대 1개라서 바깥 행 수가 늘지 않는다.

<span class="qr-k">영향</span> 원본 `EXPLAIN`에 `warehouses` 노드가 없다. PostgreSQL이 **조인 제거(join removal)**로 이미 계획에서 빼고 있어서 시간과 버퍼에 차이가 없다. 효과는 코드 정리다.

<div class="qr-bench">
  <div class="qr-bench-row">
    <span class="qr-bench-label">countStockByWarehouse · B1</span>
    <div class="qr-bench-bars">
      <div class="qr-bar-line"><span style="width:100%"></span><b>1.801</b></div>
      <div class="qr-bar-line is-after"><span style="width:98%"></span><b>1.767</b></div>
    </div>
    <span class="qr-bench-diff is-flat">-2%</span>
  </div>
  <div class="qr-bench-legend"><span><i></i>원본 (ms)</span><span><i class="is-after"></i>수정 (ms)</span><span>버퍼 34 → 34 · 결과 303건 = 303건</span></div>
</div>

<span class="qr-k">수정안</span> 조인 한 줄을 삭제한다.

</div>
</details>

<details class="qr-card is-join" id="qr-05" markdown="1">
<summary markdown="0">
  <div class="qr-card-head"><span class="qr-card-no">05</span><span class="qr-card-title">불량 합계 조회가 공유 SQL 조각 안의 routing_steps 조인을 쓰지 않는다</span><span class="qr-card-toggle"></span></div>
  <div class="qr-pills"><span class="qr-pill is-join">사용하지 않는 조인 · 공유 조각</span><span class="qr-pill is-muted">리포트</span><span class="qr-pill is-rewrite">수정안 있음</span></div>
</summary>
<div class="qr-body" markdown="1">

<span class="qr-k">대상</span> `DefectReportMapper.findDefectSummary`

<span class="qr-k">현재 코드</span> FROM 절이 `<sql>` 조각 `defectFrom`에 있고, 같은 매퍼의 쿼리 세 개가 이 조각을 `<include>`로 가져다 쓴다.

```xml
<sql id="defectFrom">
    FROM production_results PR
    INNER JOIN work_orders WO
            ON WO.work_order_id = PR.work_order_id
           AND WO.cancelled_at IS NULL
    LEFT JOIN routing_steps RS
           ON RS.work_order_id = PR.work_order_id
          AND RS.step_no       = PR.step_no
</sql>

<select id="findDefectSummary">       <!-- RS를 쓰지 않는다 -->
    SELECT SUM(PR.defect_qty) AS defect_qty
    <include refid="defectFrom"/>
</select>

<select id="findDefectTypes">         <!-- RS.process_id를 쓴다 -->
<select id="findDefectsByProcess">    <!-- RS.process_id를 쓴다 -->
```

<span class="qr-k">근거</span> `findDefectSummary` 안에서는 `RS`가 자기 ON 밖에서 쓰이지 않는다. ON 조건 (`work_order_id`, `step_no`)이 `routing_steps`의 PK를 모두 덮어서 바깥 행 수도 늘지 않는다. 이 쿼리에서는 지워도 되는 조인이다.

하지만 같은 조각을 쓰는 `findDefectTypes`와 `findDefectsByProcess`는 `RS.process_id`를 읽는다. **조각에서 조인을 지우면 이 두 쿼리가 오류가 난다.**

<span class="qr-k">영향</span> `findDefectSummary`에서만 빼면 결과는 같고, 다른 두 쿼리는 영향이 없다.

<span class="qr-k">수정안</span> 조각을 둘로 나눈다. 공통 FROM은 `defectFromBase`로 빼고, 기존 `defectFrom`은 그 위에 `RS` 조인을 더한다.

```xml
<sql id="defectFromBase">
    FROM production_results PR
    INNER JOIN work_orders WO
            ON WO.work_order_id = PR.work_order_id
           AND WO.cancelled_at IS NULL
</sql>

<sql id="defectFrom">
    <include refid="defectFromBase"/>
    LEFT JOIN routing_steps RS
           ON RS.work_order_id = PR.work_order_id
          AND RS.step_no       = PR.step_no
</sql>
```

`findDefectSummary`의 `<include refid="defectFrom"/>`만 `defectFromBase`로 바꾼다. 다른 두 쿼리는 그대로 둔다.

<span class="qr-k">실측</span> 실행 측정 대상이 아니다(사용 테이블이 1,000건 미만). 코드 점검의 두 조건만으로 확정했다.

</div>
</details>

## 점검 방법

점검은 두 단계로 했다. 실행 측정 대상 453개는 코드 점검 대상 1,695개에 포함된다.

1. **코드 점검 (1,695개)**: SQL을 실행하지 않고 매퍼의 SELECT를 Flyway 스키마와 대조했다. 없는 컬럼, 선언되지 않은 별칭, 쓰지 않는 조인을 이 단계에서 찾는다.
2. **실행 측정 (453개)**: 그중 1,000건 이상 테이블을 쓰는 쿼리만, 운영기 데이터를 이관한 개발 DB에서 직접 실행해 시간과 버퍼를 쟀다.

1·2·5번은 코드 점검만으로 확정했다. 3·4번의 실측 수치는 실행 측정에서 나왔다.

<div class="qr-notes">
  <div class="qr-note">
    <h4>실행 측정 방법</h4>
    <ul>
      <li>B1은 데이터가 가장 많은 조건 값으로, <code>&lt;if&gt;</code> 선택 조건을 모두 뺀 경우다.</li>
      <li>B2는 PK 순 중간 행으로, 값이 있는 선택 조건을 넣은 경우다.</li>
      <li>실행한 문장은 카탈로그 조회, <code>EXPLAIN</code>, <code>EXPLAIN (ANALYZE, BUFFERS)</code>, 결과 비교용 SELECT뿐이다. 소스와 DB는 바꾸지 않았다.</li>
    </ul>
  </div>
  <div class="qr-note">
    <h4>해석할 때 주의</h4>
    <ul>
      <li>서비스 오픈 전이라 데이터가 적다. 실측 시간은 대부분 수 ms 이하다.</li>
      <li>인덱스 기준(1만 건)을 만족하는 테이블이 없어 오픈 후 다시 측정해야 한다.</li>
      <li>VOLATILE 함수를 쓰는 쿼리는 <code>ANALYZE</code>로 실행하지 않았다.</li>
    </ul>
  </div>
</div>

## 정리

- 가장 많이 나온 문제는 성능이 아니라 **스키마와 맞지 않아 실행하면 오류가 나는 쿼리**였다. 호출되지 않는 화면이라 아무도 몰랐을 뿐이다.
- 별칭은 **선언된 블록 안에서만** 보인다. CTE 안의 별칭을 바깥에서 쓰면 오류가 난다.
- 조인 조건이 **자기 별칭을 참조하는지** 확인한다. 복사해서 붙인 조인은 별칭만 바뀌고 조건은 그대로인 경우가 많다.
- 쓰지 않는 LEFT JOIN은 PostgreSQL이 이미 제거할 수 있다. 이런 조인은 지워도 빨라지지 않는다. **실측으로 확인한 것만** 성능 개선이라고 말한다.
- `<sql>` 조각 안의 조인은 **그 조각을 쓰는 쿼리를 모두** 확인한 뒤에 지운다. 한 쿼리에서 필요 없어도 다른 쿼리가 쓰고 있을 수 있다.
- 수정안은 **결과 동일성**(차집합 0)과 **실측 개선**을 함께 확인한 뒤에 확정한다.

> 이 글의 쿼리는 실제 매퍼에서 핵심 부분만 남기고 줄였다. 테이블·컬럼·매퍼 이름은 실제와 다르게 바꿨다. 실측은 운영기에 붙이지 않고, 운영기 데이터를 개발기로 이관한 뒤 그 DB에서 측정했다.
{: .prompt-info }
