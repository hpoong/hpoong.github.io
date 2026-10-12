---
layout: page
title: F-MES
permalink: /projects/f-mes/
---

## Tech Stack

- **Backend**: Spring Boot
- **Frontend**: Next.js
- **Infra / CI·CD**: AWS EC2, Linux, Nginx, Docker, Jenkins Pipeline, Jenkins SSH Agent Plugin, Docker Registry, Docker Image-based Deployment, SSH, Git
- **Observability**: Grafana, Loki, Tempo, Fluent Bit, Slack

## 소개

- **팀 구성**: 백엔드 3명 / 프론트엔드 2명

제조 현장의 자재 흐름과 구매·재고 업무를 통합 관리할 수 있도록 구축한 MES 기반 업무 시스템.

입고·LOT 관리, 발주, 거래처, BOM, 기타 입출고 기능을 개발하고 CI/CD 파이프라인을 구축해 자재 관리 프로세스와 배포 운영 효율성을 함께 개선한 프로젝트.

## 주요 개발 내용

- **자재 입고 및 LOT 추적 기능 개발**
  - 자재가 입고되면 LOT 번호가 자동으로 발번되도록 하여, 현장에서 번호를 따로 매기지 않아도 되도록 개선
  - LOT 번호로 언제 어느 거래처에서 들어온 자재인지, 지금 얼마나 남았는지를 바로 확인할 수 있도록 구성
- **발주부터 입고까지 이어지는 구매 흐름 구축**
  - 발주를 등록하면 거래처 정보와 함께 관리되고, 입고 시 해당 발주를 불러와 처리할 수 있도록 연결
  - 거래처별 발주 이력을 한 화면에서 조회할 수 있도록 하여 구매 담당자의 확인 작업을 단순화
- **BOM 기반 자재 구성 관리**
  - 제품 하나를 만드는 데 필요한 자재와 수량을 BOM으로 등록하고 관리할 수 있도록 구현
  - 생산·자재 화면에서 BOM을 바로 참조하도록 연계하여, 제품별 필요 자재를 따로 찾아보지 않도록 개선
- **기타 입출고 및 재고 이력 관리**
  - 정상 입고·출고 외에 반품, 이동, 재고 조정처럼 예외적으로 생기는 입출고를 별도로 처리할 수 있도록 기능 추가
  - 모든 재고 변동을 이력으로 남겨, 수량이 맞지 않을 때 언제 어떤 작업으로 바뀌었는지 추적할 수 있도록 구성
- **CI/CD 배포 환경 구축**
  - Jenkins에서 빌드부터 Docker 이미지 생성, 운영 서버 배포까지 한 번에 진행되도록 파이프라인 구성
  - 서버에 직접 접속해 손으로 배포하던 과정을 없애 배포 시간과 실수를 줄임

## CI/CD 파이프라인 구조 개선 및 배포 서버 부하 최소화

<div class="ts-block ts-issue" markdown="1">

### 문제

- AWS EC2 운영 서버에서 애플리케이션 빌드와 서비스 실행이 함께 수행되어, 배포 시 서버 리소스 사용량이 늘고 서비스 안정성이 떨어질 수 있었음
- 서버에 직접 접속해 반복적으로 수동 배포하면서 배포 절차의 일관성이 낮았음

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 운영 서버의 역할을 애플리케이션 실행에 집중시키기 위해 **CI와 CD의 책임을 분리하는 방향으로 배포 구조를 재설계**
- 별도 Jenkins 환경에서 `Git Clone → Gradle Build → Docker Image Build → Registry Push`를 수행하고, 운영 서버에서는 Docker Image Pull과 Container 실행만 담당하도록 역할을 분리
- Docker Registry를 중심으로 빌드 결과물을 관리해 동일한 이미지를 기준으로 배포하고, Jenkins Pipeline과 SSH Agent Plugin으로 배포 절차를 자동화·표준화

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 운영 서버는 이미지 pull과 컨테이너 실행만 해서, 배포 중에 Gradle 빌드로 CPU를 쓰지 않음
- Jenkins에서 만든 이미지를 Registry에 올린 뒤 그 이미지를 운영 서버에 내림
- 서버에 SSH로 들어가 손으로 배포하던 단계를 Pipeline이 대신함

</div>

## Next.js 선택적 모듈 빌드 구조 설계 및 빌드 프로세스 단순화

<div class="ts-block ts-issue" markdown="1">

### 문제

- 고객과 배포 환경에 따라 특정 기능만 포함한 빌드가 필요했으나, 모든 기능을 담은 단일 빌드로 운영되어 불필요한 모듈 포함과 산출물 관리 복잡도가 커졌음

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 멀티 모듈 전환, 개별 빌드 설정 분리 등을 검토한 뒤, 프로젝트 규모와 유지보수 비용을 고려하여 **기능 단위 디렉토리 구조를 표준화하고 빌드 전처리 단계에서 포함 대상을 결정하는 방식으로 설계**
- 기능별 코드 위치와 의존 관계를 정형화하여 배포 대상에 필요한 모듈만 선택적으로 포함하고, 기존 애플리케이션 구조의 변경 범위를 최소화
- Jenkins Pipeline 빌드 전처리에서 배포 프로파일에 따라 제외 대상 모듈을 자동으로 정리하여, 개별 빌드 스크립트나 수동 소스 변경 없이 같은 절차로 빌드하도록 자동화

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 소스는 한 저장소로 두고, 고객에게 나가는 빌드에는 그 환경에 필요한 기능만 넣음
- 뺄 모듈은 Jenkins 전처리가 프로파일대로 정리해서, 빌드 전에 소스를 손으로 지우지 않음

</div>

## 사내 통합 Observability 및 장애 대응 체계 구축

<div class="ts-block ts-issue" markdown="1">

### 문제

- 사내 운영 서비스가 늘면서 장애 시 담당자가 개별 서버에 접속해 로그를 확인하는 방식으로 대응하여, 장애 인지와 원인 분석이 경험과 수동 확인에 의존
- 서비스 수가 늘수록 서비스별 모니터링 방식은 확장에 한계가 있었음

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 특정 서비스에 묶이지 않고 전사 서비스에서 공통으로 쓸 수 있는 **통합 Observability 환경 구축 방향을 수립**
- Grafana를 중심으로 Uptime 모니터링, 로그 수집·조회, 분산 Trace, 장애 알림을 하나의 흐름으로 연결하여 서비스 상태 → 로그 → 요청 추적 순으로 확인할 수 있도록 설계
- Fluent Bit으로 서비스·컨테이너 로그를 수집해 Loki에 저장하고, Tempo로 서비스 간 요청 흐름과 Trace를 확인할 수 있도록 구성
- Uptime 점검과 Slack 알림을 연계해 서비스 이상을 조기에 인지하도록 하고, 신규 서비스에도 같은 수집·모니터링 기준을 적용

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 서비스가 내려가면 Slack으로 먼저 알림이 옴
- 로그는 서버에 들어가지 않고 Grafana에서 서비스·환경별로 봄
- 한 요청이 어느 서비스를 지났는지는 Tempo trace로 따라감
- 새 서비스는 Fluent Bit 수집만 같은 방식으로 붙이면 같은 화면에 들어옴

</div>


---

[← Projects 목록으로 돌아가기](/projects/)
