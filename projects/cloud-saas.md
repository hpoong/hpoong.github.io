---
layout: page
title: 제조업 Cloud SaaS 플랫폼
permalink: /projects/cloud-saas/
---

## Tech Stack

- **Backend**: Spring Boot
- **Frontend**: Next.js, Angular, Web Components
- **Database**: MySQL, MariaDB, PostgreSQL (Schema-based Multi-tenancy, FDW), pgloader (Data Migration)
- **Infra / CI·CD**: Naver Cloud Platform (NKS), Docker, Kubernetes, Jenkins Pipeline, Naver Cloud Registry (NCR), JFrog Artifactory

## 소개

- **팀 구성**: 백엔드 1명 / 프론트엔드 2명

글로벌 제조 고객사를 하나의 환경에서 운영할 수 있도록 구축한 NCP Cloud SaaS 기반 제조 플랫폼.

공통 모듈 Angular 기반 MES 화면을 React 환경에 통합하고 고객사별 Schema 및 서비스 영역을 분리한 멀티테넌트 구조와 공통 모듈 배포 체계를 적용해 확장성과 운영 효율성을 높인 프로젝트.

## 주요 개발 내용

- **Angular 기반 대시보드의 React 통합**
  - Angular 컴포넌트를 Web Component로 변환하여 React 환경에서 재사용 가능한 구조로 구성
  - EventBridge와 RouterAdapter를 적용해 Angular와 React 간 이벤트 및 라우팅 연동
- **FactorySol MES 연동 기능 개발**
  - 공통 Angular 모듈을 FactorySol MES에 적용할 수 있도록 기존 백엔드 API 및 서비스 로직과 연동
  - 사용자 권한, 메뉴 정보 등 기존 MES의 인증·인가 및 화면 접근 체계와 연계하여 통합 동작하도록 구성
- **공통 모듈 배포 체계 구축**
  - 공통 라이브러리와 FactorySol MES 모듈을 패키징하여 JFrog Repository에 배포
  - 배포 아티팩트가 과도하게 누적되지 않도록 주기적으로 최근 태그 7개만 유지하는 정리 배치 개발
- **고객사별 멀티테넌트 구조 적용**
  - PostgreSQL Schema 기반으로 고객사별 데이터를 분리하여 독립적인 데이터 관리 구조 구성
  - MSA 서비스 영역도 고객사 단위로 분리하여 고객사별 기능과 데이터를 독립적으로 운영
- **FactorySol MES 전환 및 데이터 마이그레이션**
  - Angular → React 래핑 구조를 기반으로 FactorySol MES를 Cloud SaaS 환경에 배포
  - pgloader를 활용해 MariaDB 데이터를 PostgreSQL로 마이그레이션하고 데이터 검증 수행

## PostgreSQL Schema 기반 멀티 테넌시 아키텍처 설계 및 Connection 구조 개선

<div class="ts-block ts-issue" markdown="1">

### 문제

- MySQL 기반 기존 서비스 구조를 PostgreSQL 환경으로 전환하는 과정에서, 다수 테넌트의 데이터를 격리하면서도 테넌트 증가에 따른 DB Connection과 운영 복잡도를 제어할 수 있는 멀티 테넌시 구조가 필요
- 기존 테넌트별 `DataSource` 생성 방식은 테넌트 수가 늘면 Connection Pool과 Spring 설정도 함께 증가하는 구조적 한계가 있었음

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- Database-per-Tenant, Schema-per-Tenant 등 데이터 격리 방식을 검토하고, 서비스 규모와 테넌트 확장성·운영 비용을 고려하여 **PostgreSQL Schema 기반 멀티 테넌시 아키텍처를 적용**
- **단일 `DataSource`와 공유 Connection Pool**을 사용하도록 재설계하고, 요청에서 식별한 Tenant 정보를 기준으로 Connection 획득 시 `SET search_path`를 동적으로 적용
- 동일한 애플리케이션과 Connection Pool을 공유하면서 요청 단위로 대상 Schema를 전환하도록 구성하고, 테넌트별 DB 접속 설정을 애플리케이션에서 제거

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 테넌트마다 `DataSource`를 만들지 않고, 요청마다 `search_path`만 바꿔 같은 Pool을 씀
- 고객사가 늘어도 Connection Pool 설정은 하나임
- 새 테넌트를 넣을 때 애플리케이션에 DB 접속 설정을 추가하지 않음

</div>

## PostgreSQL FDW 기반 실시간 원격 데이터 조회

<div class="ts-block ts-issue" markdown="1">

### 문제

- 원본 DB와 서비스 조회 DB가 분리된 환경에서 최신 데이터를 조회해야 했으나, 별도 배치 동기화 방식은 데이터 지연과 복제 테이블 관리로 운영 복잡도가 커질 수 있었음

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 데이터 복제 방식과 원격 조회 방식을 비교한 뒤, 조회 중심 요구와 최신 데이터 정합성을 고려하여 **PostgreSQL `postgres_fdw` 기반 원격 조회 구조를 적용**
- 조회 DB에서 원본 데이터를 일반 테이블과 유사하게 사용할 수 있도록 `Foreign Server`, `User Mapping`, `Foreign Table`을 구성하여 기존 조회 로직 변경 범위를 최소화
- 원본 DB에는 FDW 조회 전용 계정을 분리하고, 필요한 Schema와 Table에만 `SELECT` 권한을 부여하여 최소 권한 원칙을 적용
- 애플리케이션이 원본 DB에 직접 연결하지 않고 조회 DB를 데이터 접근 지점으로 유지하여, 서비스 레이어와 원본 저장소 간 결합도를 낮춤

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 조회 DB에서 원본 테이블을 바로 읽어서, 동기화 배치와 복제 테이블이 없음
- 원본이 바뀌면 다음 조회에 그 값이 나옴
- 애플리케이션은 조회 DB만 접속하고, 원본 DB는 `SELECT`만 가진 FDW 계정으로 제한함

</div>

## MySQL → PostgreSQL 마이그레이션 구조 설계

<div class="ts-block ts-issue" markdown="1">

### 문제

- 서비스 데이터베이스를 MySQL에서 PostgreSQL로 전환하면서, 단순 데이터 복사가 아닌 데이터 타입·제약조건·인덱스·시퀀스 등 DBMS 간 구조 차이를 반영한 마이그레이션 전략이 필요
- `tinyint`, `datetime`, `blob`, `auto_increment` 등 타입 차이와 Foreign Key 생성 오류로, 이전 과정의 재현성과 데이터 정합성을 확보하기 어려웠음

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 반복 실행과 환경 재현이 가능하도록 Docker 기반 `pgloader` 실행 환경을 구성하고, **데이터 및 스키마 이전 과정을 설정 기반으로 표준화**
- MySQL과 PostgreSQL 간 데이터 타입 차이를 분석하고, 대상 스키마에 맞는 CAST 및 타입 변환 규칙을 정의
- 전체 테이블 일괄 이전이 아닌 대상 범위별 선택 마이그레이션으로 구성하고, PostgreSQL 환경에 맞게 PK·UNIQUE·Index·Sequence·Foreign Key 구조를 재구성
- `tinyint(1)`이 `boolean(1)`로 생성되는 문제는 `drop typemod` 규칙으로 정리하고, Foreign Key 오류(`42830`, `42804`)는 PK/UNIQUE 구성·생성 순서와 참조 컬럼 타입 매핑을 조정하여 해결

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- `pgloader` 설정이 있으면 같은 이전을 다시 실행할 수 있음
- `boolean(1)`, FK `42830`·`42804`는 변환 규칙에 넣어서 같은 오류로 중간에 멈추지 않음
- 이전 뒤에도 PK·FK 관계는 MySQL 스키마와 같게 남음

</div>

## Kubernetes 애플리케이션 실행 구조 개선 및 배포 효율화

<div class="ts-block ts-issue" markdown="1">

### 문제

- Kubernetes 환경에서 Pod 기동 시간이 길고, 스케일 아웃 시 CPU·메모리 사용량이 일시적으로 증가
- 컨테이너 시작 단계에서 `npm run build`가 반복되어, Pod 재시작과 수평 확장마다 동일한 빌드가 다시 수행되는 구조가 주요 원인

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 빌드와 런타임의 책임을 분리하여 **CI 단계에서 Frontend Build와 Docker Image 생성을 완료하고, Pod에서는 사전에 생성된 이미지만 실행하도록 배포 구조를 재설계**
- 프론트엔드 환경 변수 때문에 개발·운영 환경별 이미지 관리가 필요한 점을 고려하여, JFrog Artifactory의 dev/prod 저장소를 분리하고 이미지 버전 관리 기준을 정립
- 실행 시점의 동적 빌드에 의존하지 않고, Registry에 등록된 검증된 이미지를 기준으로 배포하도록 전환

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- Pod가 뜰 때 `npm run build`를 하지 않아 기동이 짧아짐
- 스케일 아웃할 때 빌드용 CPU·메모리를 추가로 쓰지 않음
- dev/prod 이미지가 Artifactory에 나뉘어 있어서, 배포 때는 그 환경 이미지를 그대로 가져옴

</div>


---

[← Projects 목록으로 돌아가기](/projects/)
