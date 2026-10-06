---
layout: page
title: 제조업 Cloud SaaS 플랫폼
permalink: /projects/cloud-saas/
---

## Tech Stack

- **Frontend**: Next.js, Angular, Web Components
- **Backend**: Spring Boot
- **Database**: MySQL, MariaDB, PostgreSQL
- **Infrastructure**: Naver Cloud Platform (NKS), Docker, Kubernetes
- **CI/CD**: Jenkins Pipeline, Naver Cloud Registry (NCR)
- **Artifact Management**: JFrog Artifactory
- **Data Migration**: pgloader
- **Database Architecture**: PostgreSQL Schema-based Multi-tenancy, PostgreSQL FDW

## 소개

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

- MySQL 기반 기존 서비스 구조를 PostgreSQL 환경으로 전환하는 과정에서 다수 테넌트의 데이터를 안정적으로 격리하면서도, **테넌트 증가에 따른 DB Connection 및 운영 복잡도를 제어할 수 있는 멀티 테넌시 구조 필요**
- Database-per-Tenant, Schema-per-Tenant 등 데이터 격리 방식을 검토하고, 서비스 규모와 테넌트 확장성·운영 관리 비용을 고려하여 **PostgreSQL Schema 기반 멀티 테넌시 아키텍처를 적용**
- 기존 테넌트별 `DataSource` 생성 방식은 테넌트 수 증가에 따라 Connection Pool과 Spring 설정이 함께 증가하는 구조적 한계가 있어, **단일 `DataSource`와 공유 Connection Pool을 사용하는 방식으로 재설계**
- 요청에서 식별한 Tenant 정보를 기준으로 Connection 획득 시 `SET search_path`를 동적으로 적용하여, **동일한 애플리케이션과 Connection Pool을 공유하면서 요청 단위로 대상 Schema를 전환하도록 구현**
- 각 테넌트는 독립 Schema를 통해 데이터 영역을 분리하되 애플리케이션에서는 공통 데이터 접근 구조를 유지하여, **수십~수백 개 수준으로 테넌트가 증가하더라도 DataSource를 개별 생성하지 않고 확장할 수 있는 구조 확보**
- 테넌트별 DB 접속 설정을 애플리케이션에서 제거하여 신규 Tenant 추가 시 필요한 설정 변경 범위를 줄이고, **Connection Pool·DB 접속 상태·애플리케이션 설정에 대한 운영 및 모니터링 지점을 단순화**
- 결과적으로 **데이터 격리 수준을 유지하면서 Connection 자원 사용과 설정 복잡도를 줄이고, 테넌트 증가에 유연하게 대응할 수 있는 PostgreSQL 멀티 테넌시 기반을 구축**

## PostgreSQL FDW 기반 실시간 원격 데이터 조회

- 원본 DB와 서비스 조회 DB가 분리된 환경에서 최신 데이터를 조회해야 했으나, 별도 배치 동기화 방식은 **데이터 지연과 복제 테이블 관리에 따른 운영 복잡도가 증가할 수 있는 문제**가 존재
- 데이터 복제 방식과 원격 조회 방식을 비교한 결과, 조회 중심의 요구사항과 최신 데이터 정합성을 고려하여 **PostgreSQL `postgres_fdw` 기반 원격 조회 구조를 적용**
- 조회 DB에서 원본 데이터를 일반 테이블과 유사한 방식으로 사용할 수 있도록 `Foreign Server`, `User Mapping`, `Foreign Table`을 구성하고, **기존 서비스의 조회 로직 변경 범위를 최소화**
- 원본 DB에는 FDW 조회 전용 계정을 분리하고 필요한 Schema와 Table에 대해서만 `SELECT` 권한을 부여하여 **최소 권한 원칙을 적용한 데이터 접근 구조 구성**
- 애플리케이션이 원본 DB에 직접 연결하는 방식 대신 조회 DB를 데이터 접근 지점으로 유지하여, **서비스 레이어와 원본 데이터 저장소 간 결합도를 낮추고 DB 접근 경로를 일관되게 관리**
- 별도의 데이터 복제 및 동기화 작업 없이 원본 데이터를 조회할 수 있도록 구성하여 배치 주기 관리, 동기화 실패 및 중복 데이터 관리와 같은 추가 운영 요소 최소화
- 결과적으로 **데이터 복제 없이 최신 데이터 정합성을 유지하면서 기존 서비스 구조의 변경을 최소화하고, 원격 데이터 조회에 필요한 운영 및 권한 관리 체계를 단순화**

## MySQL → PostgreSQL 마이그레이션 구조 설계

- 서비스 데이터베이스를 MySQL에서 PostgreSQL로 전환하는 과정에서 단순 데이터 복사가 아닌 **데이터 타입, 제약조건, 인덱스, 시퀀스 등 DBMS 간 구조 차이를 고려한 마이그레이션 전략 수립**
- 반복 실행과 환경 재현이 가능하도록 Docker 기반 `pgloader` 실행 환경을 구성하고, **데이터 및 스키마 이전 과정을 설정 기반으로 관리할 수 있도록 마이그레이션 절차 표준화**
- MySQL과 PostgreSQL 간 `tinyint`, `datetime`, `blob`, `auto_increment` 등의 데이터 타입 차이를 분석하고, 대상 스키마에 적합한 **CAST 및 타입 변환 규칙을 정의하여 데이터 정합성 확보**
- 전체 테이블을 일괄 이전하는 방식이 아닌 대상 범위에 따라 선택적으로 마이그레이션할 수 있도록 구성하고, PostgreSQL 환경에 맞게 **PK·UNIQUE·Index·Sequence·Foreign Key 구조를 재구성**
- 데이터 이전 과정에서 발생하는 타입 불일치와 제약조건 생성 오류를 단순 예외 처리하지 않고 원인을 분석하여 변환 규칙과 실행 순서를 조정함으로써 **재실행 가능한 안정적인 마이그레이션 구조 확보**
- 마이그레이션 이후 테이블 구조와 참조 관계를 검증하여 원본 MySQL 스키마의 논리적 관계가 PostgreSQL에서도 유지되도록 하고, 애플리케이션 전환에 필요한 DB 구조 정합성 확보
- 결과적으로 DBMS 차이로 발생하는 변환 이슈를 사전에 규칙화하고 **데이터 이전, 스키마 변환, 제약조건 재구성까지 포함한 반복 가능한 마이그레이션 체계 구축**

### 주요 트러블슈팅

- `tinyint(1)`을 PostgreSQL `boolean`으로 변환하는 과정에서 typemod가 유지되어 `boolean(1)` 형태로 생성되는 문제를 확인하고, `drop typemod` 규칙을 적용하여 정상적인 Boolean 타입으로 변환
- Foreign Key 생성 과정에서 PostgreSQL 오류 코드 `42830`이 발생하여 참조 대상 컬럼의 제약조건을 분석하고, **PK/UNIQUE 구성 및 Index·Foreign Key 생성 순서를 조정하여 참조 무결성 확보**
- 원본과 대상 테이블 간 `numeric` / `bigint` 타입 차이로 Foreign Key 생성 오류 `42804`가 발생하여 컬럼 간 타입 매핑 규칙을 재정의하고, **참조 컬럼의 데이터 타입을 일관되게 변환하도록 마이그레이션 규칙 보완**

## Kubernetes 애플리케이션 실행 구조 개선 및 배포 효율화

- Kubernetes 환경에서 Pod 기동 시간이 길고 스케일 아웃 시 CPU·메모리 사용량이 일시적으로 증가하는 현상을 분석한 결과, **컨테이너 시작 단계에서 `npm run build`가 반복 수행되는 구조가 주요 원인임을 확인**
- 애플리케이션 실행 시점에 빌드를 수행하는 구조는 Pod 재시작 및 수평 확장마다 동일한 작업을 반복하게 되어 Kubernetes의 빠른 기동 및 확장 특성을 저해한다고 판단
- 빌드와 런타임의 책임을 분리하여 **CI 단계에서 Frontend Build와 Docker Image 생성을 완료하고, Pod에서는 사전에 생성된 이미지 실행만 담당하도록 배포 구조 재설계**
- 이를 통해 동일한 애플리케이션 버전에 대해 빌드가 반복되지 않도록 하고, Kubernetes Runtime이 애플리케이션 실행과 스케일링에만 집중할 수 있도록 구조 단순화
- 프론트엔드 환경 변수 처리 방식으로 인해 개발·운영 환경별 이미지 관리가 필요한 점을 고려하여 **JFrog Artifactory의 dev/prod 저장소를 분리하고 이미지 버전 관리 기준을 정립**
- 실행 시점의 동적 빌드에 의존하지 않고 Registry에 등록된 검증된 이미지를 기준으로 배포하도록 전환하여 **배포 결과의 재현성과 환경별 이미지 관리 일관성 확보**
- 결과적으로 Pod 기동 지연과 불필요한 빌드 리소스 사용을 제거하고, **스케일링 대응 속도와 배포 안정성을 높이는 Kubernetes 실행 구조로 개선**

---

[← Projects 목록으로 돌아가기](/projects/)
