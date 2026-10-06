---
# 스타일은 _sass/custom/_troubleshooting.scss 에서 관리합니다.
layout: page
title: 장애 대응 사례
icon: fas fa-screwdriver-wrench
order: 5
---

<nav class="ts-index" aria-label="사례 목록">
  <a class="ts-index-item" href="#docker-log">
    <span class="ts-index-no">01</span>
    <span class="ts-index-title">Docker 로그 I/O 장애 원인 분석 및 로그 운영 체계 개선</span>
    <span class="ts-tags"><span>Docker</span><span>AWS EC2</span></span>
  </a>
  <a class="ts-index-item" href="#nextjs-security">
    <span class="ts-index-no">02</span>
    <span class="ts-index-title">Next.js 보안 취약점 대응 및 운영 서버 보안 강화</span>
    <span class="ts-tags"><span>Next.js</span><span>Security</span></span>
  </a>
  <a class="ts-index-item" href="#shared-pool">
    <span class="ts-index-no">03</span>
    <span class="ts-index-title">Shared Pool 문제 해결</span>
    <span class="ts-tags"><span>HikariCP</span><span>PostgreSQL</span></span>
  </a>
</nav>

<section class="ts-case" id="docker-log" markdown="1">

<header class="ts-case-head">
  <span class="ts-case-no">01</span>
  <div>
    <h2 class="ts-case-title">Docker 로그 I/O 장애 원인 분석 및 로그 운영 체계 개선</h2>
    <span class="ts-tags"><span>Docker</span><span>AWS EC2</span></span>
  </div>
</header>

<div class="ts-shots ts-shots-wide" markdown="1">

![service-app DB 쓰기 장애: 현상부터 검증까지](/assets/img/troubleshooting/docker-log-1.png){: w="1600" h="815" }

![재발 방지 및 로그 운영 기준](/assets/img/troubleshooting/docker-log-2.png){: w="1600" h="847" }

</div>

<div class="ts-block ts-issue" markdown="1">

### 현상 및 영향

Docker 기반 EC2 운영 환경에서 조회 기능은 정상 동작했으나, INSERT·UPDATE를 사용하는 쓰기 기능에서 장애 발생<br>서버 상태 점검 결과 EC2 디스크 사용량의 한계 도달 확인

- 영향 기능: 결제 처리 과정에서 오류 발생. 조회 기능은 이용 가능했으나 데이터 생성·수정이 필요한 쓰기 기능 처리 실패
- 장애 확인 근거: 조회와 쓰기 작업 간 동작 차이 확인 서버 점검에서 디스크 공간 부족과 Docker 로그 누적 확인 후 로그 정리 및 공간 확보를 통해 쓰기 기능 정상화

</div>

<div class="ts-block ts-cause" markdown="1">

### 원인 분석

애플리케이션과 DB에 한정하지 않고 서버 파일 시스템까지 장애 분석 범위를 확장하여 디스크 사용량 및 대용량 파일 추적<br>`/var/lib/docker/containers` 경로에 Docker 컨테이너의 `json.log` 파일이 지속적으로 누적되고 있는 현상 확인

| 확인 항목 | 확인 내용 | 판단 근거 |
| --- | --- | --- |
| 애플리케이션 동작 | 조회 API는 정상 응답, 등록·수정 등 데이터 변경 요청에서만 오류 발생 | 읽기는 성공하고 쓰기만 실패하는 비대칭 증상으로 보아, 애플리케이션 로직보다 저장 계층의 쓰기 경로 문제로 범위를 좁힘 |
| 파일시스템 상태 | EC2 루트 파일시스템 사용량이 한계 수준에 도달 | `df -h`로 마운트별 사용률을 확인해 루트 파일시스템 고갈을 특정하고, `du`·`find`·`sort`로 용량 점유 지점을 추적 |
| 주요 용량 점유 파일 | `/var/lib/docker/containers` 크기가 비정상적으로 증가 | 컨테이너별 로그 크기를 비교해 특정 애플리케이션 컨테이너의 로그가 단독으로 대부분의 용량을 점유하고 있음을 확인 |
| 로그 누적 원인 | Docker 기본 `json-file` 드라이버를 크기 제한·Rotation 설정 없이 사용해 로그가 무제한 적재 | `json-file` 드라이버에 `max-size`·`max-file` 설정이 없어 로그 파일 크기에 상한이 없었으며, 로그가 호스트 루트 파일시스템에 지속적으로 누적되는 구조임을 확인 |

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- `service-app` 컨테이너의 대용량 JSON 로그 파일을 우선 정리하여 EC2 디스크 공간 확보
- 약 18.4GB까지 누적된 로그 파일에 `truncate` 적용 후 디스크 사용률 감소 확인
- 공간 확보 후 `service-app`의 INSERT·UPDATE 샘플 검증 및 동일 EC2 내 기타 서비스의 쓰기 동작 확인
- 재발 방지를 위해 로그 로테이션 설정 적용: `max-size=500m`, `max-file=3`
- 디스크 사용률 경고 80%·위험 90%, 단일 컨테이너 로그 일일 증가량 1GB 이상을 점검 기준으로 설정

</div>

<div class="ts-block ts-verify" markdown="1">

### 검증 및 결과

<div class="ts-compare" markdown="1">

| 검증 항목 | 조치 전 | 조치 후 |
| --- | --- | --- |
| EC2 디스크 사용률 | 100% | 72% |
| 주요 컨테이너 로그 크기 | 약 18.4GB | 정리 직후 약 12MB |
| `service-app` 쓰기 동작 | INSERT·UPDATE 실패 | 샘플 검증 정상 |
| 동일 EC2 내 기타 서비스 | 쓰기 영향 여부 점검 필요 | 쓰기 동작 정상 확인 |
| 로그 보관 설정 | 로테이션 미설정 | 파일당 500MB·최대 3개 설정 |

</div>

- **장애 발생:** 2026-01-13 17:00 KST
- **장애 감지:** 17:08 — 발생 후 8분
- **복구 완료:** 17:26 — 감지 후 18분, 전체 장애 지속 26분
- **복구 결과:** 디스크 공간 확보 후 INSERT·UPDATE 정상 동작 확인 및 서비스 쓰기 장애 해소
- **운영 개선:** 대용량 로그 식별 → 공간 확보 → 쓰기 검증 절차 문서화 및 로그 보관·디스크 점검 기준 수립

</div>

<div class="ts-block ts-prevent" markdown="1">

### 재발 방지

컨테이너 로그의 무제한 누적을 방지하기 위한 로테이션 설정 적용. 디스크 사용률·로그 증가량 기반 점검 기준 수립 및 장애 대응 절차 문서화.

| 운영 기준 | 실제 적용 내용 |
| --- | --- |
| 점검 대상 | EC2 파일시스템 사용률 및 컨테이너별 JSON 로그 크기·일일 증가량 |
| 점검 주기·기준 | 매일 09:00 디스크 사용률 및 로그 용량 상위 5개 컨테이너 점검. 디스크 사용률 80% 이상 경고·90% 이상 위험 경고 기준 설정 |
| 로그 보관 설정 | `service-app`에 `json-file` 로테이션 적용. `max-size=500m`, `max-file=3`으로 설정하고, Compose 변경·배포 시 설정 유지 여부 점검 |
| 알림 | 디스크 사용률 80% 이상 시 Slack 알림. 로그 증가량 기준 초과 시 해당 서비스의 로그 레벨·로테이션 설정 점검 |
| 로그 발생량 관리 | 디버그·요청 본문 등 과다 출력 원인 확인. INFO 레벨 유지 기준 수립 및 대용량 덤프 출력 제거를 후속 배포 과제로 관리 |
| 대응 절차 | 디스크 상태 확인 → 대용량 로그 우선 식별·정리 → INSERT·UPDATE 정상 동작 검증 → 원인 서비스의 로그 레벨·보관 설정 점검 |
| 문서화 | 점검 명령어, 임계값, 로그 정리 및 쓰기 검증 순서를 운영 Runbook에 반영 |

</div>

</section>

<section class="ts-case" id="nextjs-security" markdown="1">

<header class="ts-case-head">
  <span class="ts-case-no">02</span>
  <div>
    <h2 class="ts-case-title">Next.js 보안 취약점 대응 및 운영 서버 보안 강화</h2>
    <span class="ts-tags"><span>Next.js</span><span>Security</span></span>
  </div>
</header>

<div class="ts-shots ts-shots-wide" markdown="1">

![Next.js RCE 공격 서비스 장애: 현상부터 검증까지](/assets/img/troubleshooting/nextjs-security.png){: w="1600" h="840" }

</div>

<div class="ts-block ts-cause" markdown="1">

### 원인 분석

애플리케이션 로그와 실행 중인 프로세스를 점검하여 일반적인 요청 처리 오류와 공격 관련 흔적을 구분. 외부 스크립트 다운로드, 셸 실행, 실행 권한 확인 및 지속 실행 환경 확보를 시도하는 패턴 식별.

| 확인 항목 | 확인 내용 | 판단 근거 |
| --- | --- | --- |
| 서비스·서버 상태 | 서비스 전체 중단과 CPU·메모리 사용량 급증 | 비정상 요청 및 자원 사용 증가를 중심으로 장애 원인 추적 |
| 명령 실행 관련 로그 | Command failed, bash: not found 등 확인 | 외부 명령 실행 시도와 일부 실행 실패 흔적 식별 |
| 외부 스크립트 다운로드 | curl, wget 및 스크립트 경로 포함 | 외부 파일 다운로드·실행 시도 패턴 식별 |
| 실행 권한·메타데이터 탐색 | uid=0(root), meta-data/iam 관련 문자열 확인 | 실행 권한 확인 및 클라우드 자격증명 탐색 의심 흔적 식별 |
| 지속 실행 시도 | systems-update-service 등 systemd 관련 패턴 | 서비스 등록을 통한 지속 실행 시도 정황 식별 |
| 외부 콜백 | requestrepo 관련 문자열 확인 | 외부 콜백을 이용한 실행 여부 확인 의심 패턴 식별 |

</div>

<div class="ts-block ts-stats" markdown="1">

### 로그 키워드 집계

| 키워드 | 집계 건수 |
| --- | --- |
| `requestrepo` | 15 |
| `Command failed` | 13 |
| `SyntaxError` | 13 |
| `bash: not found` | 8 |
| `wget timeout` | 5 |

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 취약한 Next.js 버전을 보안 패치가 반영된 버전으로 업그레이드하고 관련 의존성 보안 상태 점검
- 공격 관련 실행 경로와 서버 설정 점검 및 불필요한 접근·실행 경로 정비
- 반복적으로 관측된 명령 실행·외부 접속 관련 로그 패턴을 모니터링 대상으로 등록

</div>

<div class="ts-block ts-verify" markdown="1">

### 검증 및 결과

<div class="ts-compare" markdown="1">

| 검증 항목 | 조치 전 | 조치 후 |
| --- | --- | --- |
| 서비스 이용 상태 | 서비스 전체 중단 | 서비스 정상화 |
| 서버 자원 상태 | CPU·메모리 사용량 급증 | 이미지 기록 기준 자원 소모·서비스 장애 해소 |
| Next.js 보안 상태 | 15.1.5 사용 | 보안 패치 버전으로 업그레이드 |
| 공격 관련 로그 관리 | 장애 분석 과정에서 관련 패턴 식별 | 동일 패턴에 대한 로그 모니터링 체계 정립 |

</div>

- **장애 발생:** 2025-07-13
- **장애 감지:** 2025-07-14 — 발생 다음 날
- **복구 완료:** 2025-07-14 — 감지 당일 복구
- **복구 성과:** 전체 중단된 서비스 정상화 및 취약점 패치 적용
- **운영 개선:** 공격 관련 로그 패턴을 기준으로 후속 관찰이 가능한 모니터링 기준 정리
- **측정 범위:** 시각 단위 기록과 조치 전후 자원 사용률 수치 미확인으로 정확한 복구 소요 시간·자원 감소율 산정 제외

</div>

<div class="ts-block ts-prevent" markdown="1">

### 재발 방지

애플리케이션 보안 패치 상태와 공격 관련 로그를 함께 점검하는 운영 기준 수립. 확인된 공격 패턴의 재유입 및 유사 실행 시도를 관찰하도록 모니터링 보완.

| 운영 기준 | 적용 내용 |
| --- | --- |
| 보안 패치 관리 | Next.js 및 관련 의존성의 취약점·보안 패치 상태 점검 |
| 공격 패턴 모니터링 | 외부 스크립트 다운로드, 셸 실행, systemd 등록 및 외부 콜백 관련 로그 관찰 |
| 실행 실패 로그 분석 | `Command failed` 등 오류 발생 시 포함된 명령·대상 경로를 함께 확인하여 공격 관련 여부 구분 |
| 접근·실행 경로 관리 | 장애 대응 과정에서 확인한 불필요한 접근·실행 경로 정비 |

</div>

</section>

<section class="ts-case" id="shared-pool" markdown="1">

<header class="ts-case-head">
  <span class="ts-case-no">03</span>
  <div>
    <h2 class="ts-case-title">Shared Pool 문제 해결</h2>
    <span class="ts-tags"><span>HikariCP</span><span>PostgreSQL</span></span>
  </div>
</header>

<div class="ts-shots ts-shots-wide" markdown="1">

![Shared Pool 커넥션 고갈 장애: 현상부터 검증까지](/assets/img/troubleshooting/shared-pool.png){: w="1600" h="875" }

</div>

<div class="ts-block ts-issue" markdown="1">

### 현상

B2B SaaS 서비스에서 배치 실행 중 HikariCP connection timeout이 발생하고, 전 테넌트 일반 API가 함께 지연·실패<br>로그·DB 세션 점검 결과 shared connection pool 고갈 확인

- 영향 기능: 배치뿐 아니라 동일 pool을 사용하는 전 테넌트 조회·등록 API까지 지연·실패. 테넌트별 pool 구조에서는 한 테넌트에 국한되던 영향이 shared pool 단일화 이후 전 테넌트로 전파
- 장애 확인 근거: 앱 로그에서 `Connection is not available, request timed out after 10000ms`와 작업 트랜잭션 개설 실패를 확인하고, PostgreSQL 세션 수가 pool size에 도달한 것을 대조하여 커넥션 고갈을 특정

</div>

<div class="ts-block ts-cause" markdown="1">

### 원인 분석

애플리케이션 로그, Hikari pool 상태, PostgreSQL `pg_locks`·`pg_stat_activity`를 대조해 단순 부하 증가와 커넥션 고갈을 구분했다. <br>특히 **배치 1건이 점유하는 커넥션 수를 코드 기준으로 다시 세는 것**이 분석의 전환점이었다.

| 확인 항목 | 확인 내용 | 판단 근거 |
| --- | --- | --- |
| 락 구현 구조 | `executeWithLock`이 shared pool에서 커넥션을 꺼내 락 유지용으로 잡은 뒤, 그 커넥션을 쥔 상태로 `task.run()`을 실행 | 자기가 점유한 자원을 놓지 않고 같은 유한 pool에 추가 요청하는 hold-and-wait 성립. PostgreSQL advisory lock이 세션(커넥션) 종속이라는 특성 때문에 구조적으로 강제된 점유였음 |
| 커넥션 점유 수 | 최초 계산은 `락 1 + 작업 1 = 2`였으나, 실제 획득 지점은 4곳이고 **동시 점유는 최대 3** | orchestrator 바깥 `@Transactional` 1개 + 채번·알림의 `REQUIRES_NEW` 1개가 추가. `REQUIRES_NEW`는 바깥 트랜잭션을 suspend하지만 **suspend된 트랜잭션의 커넥션은 반납되지 않는다** |
| 알림 발송 시점 | `@TransactionalEventListener(AFTER_COMMIT)` 구간에서도 점유가 3으로 유지 | Spring의 AFTER_COMMIT 콜백은 커밋 직후·커넥션 정리 **이전**에 실행되므로, 배치 막바지에도 점유가 줄지 않음 |
| 트랜잭션 범위 | `@Transactional`이 업체별 루프·cycle 루프를 통째로 감싸는 메서드 단위 | 처리 대상이 많을수록 커넥션 1개의 보유 시간이 선형 증가. 채번 중복 시 `50ms × 최대 10회` 재시도가 붙어 점유 시간이 추가로 증가 |
| 분산 락의 한계 | lock key A01~A05가 서로 달라 5개 배치가 모두 락 획득에 성공 | advisory lock은 **같은 작업의 중복 실행만** 막는다. 서로 다른 배치가 각각 커넥션을 점유하는 것은 막지 못함 |

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

커넥션 고갈의 직접 원인인 락 커넥션을 main pool에서 제거하고, 점유 시간을 결정하는 트랜잭션 범위를 축소했다.

- **락 커넥션 분리:** advisory lock 유지용 커넥션을 main pool이 아닌 **별도 소규모 DataSource**에서 획득하도록 변경. 락 점유가 서비스 트래픽용 pool을 잠식하지 않게 되어 hold-and-wait 자체를 해소
- **트랜잭션 범위 축소:** orchestrator의 메서드 단위 `@Transactional`을 업체별 단위로 좁혀 바깥 트랜잭션의 커넥션 보유 시간 단축. 처리 대상 증가에 점유 시간이 선형 비례하던 구조 제거
- **pool 용량 명시:** `maximum-pool-size`를 프로파일에 명시해 라이브러리 기본값 의존 제거. `인스턴스 수 × pool size`가 PostgreSQL `max_connections` 안에 들어오도록 산정
- **실패 가시성 확보:** 락 획득 단계 실패(`Advisory Lock 처리 중 SQLException 발생`)와 작업 단계 실패(`배치 작업 실행 중 오류 발생`)를 분리 기록하고, 인프라 고갈을 정상적인 중복 실행 방지와 구분

</div>

<div class="ts-block ts-prevent" markdown="1">

### 재발 방지

이번 결함은 개별 코드의 버그가 아니라 **"shared pool로 통합하면서 이전 구조의 커넥션 점유 가정이 함께 옮겨오지 않은"** 데서 발생했다. 따라서 동일 패턴을 코드 리뷰와 모니터링 양쪽에서 걸러내는 기준을 세웠다.

| 운영 기준 | 실제 적용 내용 |
| --- | --- |
| 커넥션 점유 구조 검토 | 락·바깥 트랜잭션·`REQUIRES_NEW`가 동일 pool을 중첩 요청하는 경로를 코드 리뷰 고정 항목으로 등록. 특히 외부 자원을 점유한 채 같은 pool을 재요청하는 코드를 금지 패턴으로 명시 |
| 트랜잭션 범위 기준 | 루프를 감싸는 메서드 단위 `@Transactional`을 리뷰 지적 대상으로 지정. 처리 건수에 비례해 커넥션 보유 시간이 늘어나는 구조를 사전 차단 |
| pool 용량 관리 | 전 프로파일에 `maximum-pool-size` 명시를 필수화하고, 배포 전 `인스턴스 수 × pool size ≤ DB max_connections` 검증 |
| 모니터링 | `hikaricp_connections_pending`, `idle in transaction` 세션 수, advisory lock 보유 건수를 알람 대상으로 등록. 커넥션 대기가 timeout으로 번지기 전 감지 |

</div>

</section>
