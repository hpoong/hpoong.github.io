---
layout: page
title: 오일타임
permalink: /projects/oiltime/
---

## Tech Stack

- **Backend**: Spring Boot, Spring Boot ApplicationRunner (Batch), Maven
- **Frontend**: Next.js
- **Database / Search**: MySQL (Partitioning), Redis, Meilisearch
- **Infra / CI·CD**: AWS, Docker, Docker Compose, Nginx, Jenkins Pipeline, GitLab Container Registry, GitLab Package Registry

## 소개

- **팀 구성**: 백엔드 1명 / 프론트엔드 2명

자동차 정비 예약과 차량 관련 상품 구매를 하나로 통합해 제공하는 모빌리티 커머스 플랫폼.

위치 기반 카센터 검색부터 예약·결제까지의 사용자 서비스와, 정비업체(카센터)를 위한 제품 구매·고객 예약 관리 B2B 서비스를 함께 구축·운영한 프로젝트.

## 주요 개발 내용

- **위치 기반 카센터 검색 및 예약 기능 고도화**
  - 사용자 위치를 기준으로 반경 10km 내 카센터 정보를 조회할 수 있도록 기능 개선
  - 위도·경도 정보를 활용해 지도에서 가맹점 위치와 예약 가능 여부를 직관적으로 확인할 수 있도록 구성
  - 카센터 목록에서 예약 가능한 시간을 바로 확인할 수 있도록 개선
  - 평일·주말·점심시간 등 영업 조건에 따라 예약 가능/불가 시간을 세분화하여 예약 정책을 유연하게 관리할 수 있도록 개선
- **결제 및 알림 서비스 확장**
  - 기존 결제 방식에 네이버페이와 카카오페이를 추가하여 사용자 결제 편의성 강화
  - 예약, 주문, 시스템, 광고 등 서비스 이벤트에 따라 알림톡을 발송할 수 있도록 기능 확장
  - 푸시 알림 기능을 추가하여 주요 서비스 상태 및 안내 정보를 사용자에게 빠르게 전달할 수 있도록 개선
  - 관리자에서 광고성·시스템성 알림톡을 구분하여 발송하고 관리할 수 있도록 운영 기능 추가
- **지역 및 상품 검색 사용자 경험 개선**
  - 사용자 입력 오류를 고려해 오타가 포함된 검색어도 원하는 상품을 찾을 수 있도록 상품 검색 기능 개선
  - 검색 정확도와 접근성을 높여 사용자가 원하는 카센터 및 상품을 보다 쉽게 찾을 수 있도록 사용자 경험 개선
- **쇼핑몰 및 관리자 기능 전면 개선**
  - 상품 탐색과 구매 흐름을 중심으로 쇼핑몰 화면 및 기능 전반을 개선
  - 기존 대/중/소 형태로 고정되어 있던 상품 카테고리를 동적으로 구성할 수 있도록 구조 변경
  - 카테고리 추가·변경에 대한 운영 유연성을 확보하여 상품 확장 및 관리 편의성 향상
  - 사용자 서비스와 관리자 운영 기능을 함께 개선하여 예약, 상품, 알림, 결제까지 전체 서비스 흐름을 고도화

## 분산 Batch → 독립 Batch Runner 아키텍처 전환

<div class="ts-block ts-issue" markdown="1">

### 문제

- `consumer-service`, `partner-service`, `operation-service`에 Redis 인기 검색어 집계, Meilisearch 인덱스 생성, 좌표 데이터 처리 등의 배치 로직이 분산
- 배치 로직만 변경해도 해당 사용자 서비스의 배포가 필요했고, 서비스마다 실행 방식이 달라 작업 실행 및 장애 대응 과정에서 운영 복잡도 증가

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 배치 실행 책임을 사용자 서비스에서 분리하고, Spring Boot 기반의 **독립 Batch Runner로 통합**
- `ApplicationRunner`와 환경 변수 `MODE`를 활용해 작업 유형별로 배치를 선택적으로 실행할 수 있도록 구성
- Redis, Meilisearch, 좌표 처리 등 서로 다른 배치 작업을 공통 실행 구조로 통합
- Jenkins Parameter와 연계하여 서버 접속 없이 필요한 배치를 선택하고 실행하도록 운영 절차 표준화

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 배치만 고칠 때는 `consumer-service` 등 사용자 서비스를 다시 배포하지 않아도 됨
- Jenkins에서 `MODE`만 골라 실행해서, 서버에 들어가 배치를 직접 돌리지 않음
- 인기 검색어, 인덱스, 좌표 처리가 한 Runner에 모여 있어 장애 나면 볼 곳이 한곳임

</div>

## 3개 서비스 공통 비즈니스 로직 모듈화

<div class="ts-block ts-issue" markdown="1">

### 문제

- `consumer-service`, `partner-service`, `operation-service`에 동일하거나 유사한 비즈니스 로직이 중복 구현
- 공통 기능 변경 시 여러 서비스를 반복 수정해야 했으며, 서비스별 구현 차이로 코드 일관성과 유지보수성 저하
- 기존 프로젝트 구조상 Multi Module 전환이 어려워 독립적인 공통 모듈 관리 방식 필요

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 중복된 비즈니스 로직을 서비스에서 분리하고, Maven 기반의 **외부 공통 Library로 모듈화**
- 3개 서비스에서 재사용 가능한 비즈니스 로직을 공통 Library로 분리하여 중복 구현 최소화
- GitLab Package Registry를 활용해 공통 Library를 패키지로 배포하고 서비스별 의존성 버전 관리 체계 구축
- 각 서비스가 필요한 시점에 검증된 버전을 선택적으로 적용하도록 구성하여 공통 Library와 서비스 배포 주기 분리

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 공통 로직을 고칠 때 서비스 세 곳을 같이 수정하지 않고 Library만 고침
- 서비스마다 Library 버전을 따로 올려서, 한 서비스 배포에 나머지를 묶지 않음
- 같은 기능이 서비스마다 조금씩 달랐던 부분이 Library 한 버전으로 맞춰짐

</div>

## 대용량 알림 이력 파티셔닝 및 데이터 Lifecycle 자동화

<div class="ts-block ts-issue" markdown="1">

### 문제

- `notification_send_history` 테이블에 알림 발송 이력이 지속적으로 누적되면서 테이블 및 인덱스 크기가 증가하고, 보관 기간이 지난 데이터를 정리해야 하는 운영 부담 발생
- 기존 대량 `DELETE` 방식은 삭제 과정에서 DB 부하와 트랜잭션 로그 증가를 유발하며, 데이터가 늘수록 정기 삭제 작업의 부담도 함께 커지는 구조

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 데이터 증가에 대응하고 보관 정책을 효율적으로 관리하기 위해 **MySQL 월 단위 Range Partitioning 및 데이터 Lifecycle 자동화** 구조 적용
- 알림 발생 시점을 기준으로 월별 Range Partition을 구성하여 데이터 저장 및 관리 단위를 분리
- 보관 기간이 지난 데이터는 대량 `DELETE` 대신 Partition 단위로 제거하도록 변경하여 데이터 정리 비용 최소화
- Jenkins Pipeline을 활용해 신규 Partition 사전 생성 및 보관 기간이 만료된 Partition 정리 작업 자동화

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 보관 기간이 지난 달은 행을 `DELETE`하지 않고 해당 월 Partition을 떼어냄
- 다음 달 Partition 생성과 만료 Partition 삭제를 Jenkins가 실행함
- 알림 이력이 늘어도 지우는 단위는 월 Partition 하나로 유지됨

</div>


---

[← Projects 목록으로 돌아가기](/projects/)
