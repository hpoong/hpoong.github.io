---
layout: page
title: 통합 연계 및 서비스 고도화
permalink: /projects/integration/
---

## Tech Stack

- **Backend**: Spring Boot
- **Frontend**: Angular 17, TypeScript, RxJS, Nx (Monorepo), BroadcastChannel API
- **Database / Data Analysis**: MariaDB, InfluxDB, JupyterLab, IPython
- **Infra / Build**: Nginx, Node.js 20, npm, JFrog Artifactory, npm Package

## 소개

- **팀 구성**: 백엔드 1명 / 프론트엔드 2명

에너지 설비 데이터를 실시간으로 모니터링하고 분석할 수 있도록 구축한 통합 대시보드 플랫폼.

임계치 기반 알림, 데이터 연산 및 시각화, 카드 간 상호작용 기능을 고도화하고 Angular 10 → 17 업그레이드와 JupyterLab·InfluxDB 분석 환경 표준화를 통해 서비스 안정성과 개발·분석 환경을 함께 개선한 프로젝트.

## 주요 개발 내용

- **임계치 기반 실시간 알림 기능 개발**
  - KPI, 게이지, 생키 등 대시보드 카드별 한계치 정보를 기준으로 임계 영역 진입·해제 상태를 감지하고 알림을 생성하도록 구현
  - 사용자별 푸시 알림 권한 및 기능 활성 여부를 관리하여 권한에 따라 알림을 수신할 수 있도록 구성
- **대시보드 데이터 상호작용 및 분석 기능 고도화**
  - 작화 표·차트에서 선택한 데이터를 대시보드 변수와 연계하여 관련 카드 데이터를 동적으로 변경하도록 구현
  - 카드별 Date Picker와 월 Trend 차트를 추가하여 기간별 이력 데이터와 상·하한선을 직관적으로 확인할 수 있도록 개선
- **대시보드 연산 및 시각화 기능 확장**
  - Point, Web Point, RDB 데이터, 상수값을 조합하여 하나의 연산식으로 처리할 수 있는 웹 연산 기능 구현
  - 지도 시각화 차트와 Polar Diagram 등 신규 대시보드 카드 유형을 추가하여 데이터 표현 방식 확장
- **프론트엔드 기술 스택 현대화**
  - 장기간 운영된 Angular 10 기반 레거시 환경을 Angular 17로 업그레이드하여 최신 라이브러리 적용 기반 확보
  - 패키지 간 버전 충돌과 보안 업데이트 대응 문제를 개선하고 프론트엔드 개발 환경 전반을 최신화
- **JupyterLab 데이터 분석 환경 표준화**
  - Notebook마다 반복되던 InfluxDB Connection 초기화 코드를 공통화하여 분석 코드 중복 제거
  - JupyterLab 커널 시작 시 공통 Connection을 자동 초기화하도록 구성하여 사용자별 실행 환경 편차를 최소화
- **로그인 및 사용자 편의 기능 개선**
  - Broadcast 기능을 활용하여 한 브라우저 내 여러 탭의 로그인 상태를 실시간으로 동기화하도록 자동 로그인 기능 구현
  - 로그인 페이지 이미지를 관리자가 등록·변경할 수 있도록 설정 기능 추가

## Angular 프레임워크 10 → 17 버전 업그레이드

<div class="ts-block ts-issue" markdown="1">

### 문제

- Angular 10 기반 레거시 환경이 오래 유지되면서 최신 라이브러리 적용 제약, 패키지 간 버전 충돌, 보안 업데이트 대응이 어려워짐
- Angular 버전만 올려서는 Node.js, Nx, TypeScript, RxJS 등 연관 개발 생태계의 호환성 문제가 함께 남아 있었음

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 연관 생태계 호환성을 함께 분석하여 **Angular 17을 기준으로 프론트엔드 개발 환경 현대화 방향을 수립**
- 주요 버전 간 Breaking Change와 의존성 호환 범위를 확인하며 단계적으로 마이그레이션하고, Node.js 20 기반으로 Runtime과 Build 환경을 함께 정비
- Nx를 `8.5.0 → 18.20.0`으로 올리면서 Workspace와 Build 설정을 최신 구조에 맞추고, Angular·TypeScript·RxJS 핵심 의존성 버전을 같은 기준으로 재구성
- Angular CLI와 RxJS API 변경으로 생긴 호환 문제를 애플리케이션 코드와 빌드 설정에서 수정하여, 기존 기능을 유지한 채 최신 프레임워크 환경으로 전환

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 기존 화면이 Angular 17, Nx 18.20.0, Node.js 20에서 빌드되고 동작함
- Angular 10에 묶여 올리지 못하던 패키지와 보안 패치를 적용할 수 있는 버전이 됨

</div>

## JupyterLab 데이터 분석 환경 표준화 및 InfluxDB 연결 자동화

<div class="ts-block ts-issue" markdown="1">

### 문제

- JupyterLab 분석 과정에서 Notebook마다 InfluxDB Connection 초기화 코드가 반복 작성됨
- 사용자별 접속 설정 차이로 분석 코드 중복과 실행 환경 편차가 발생

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 분석 로직과 DB 연결 설정의 책임을 나누기 위해 **JupyterLab 커널 시작 시 공통 Connection을 자동으로 초기화하는 실행 구조로 개선**
- IPython `startup` 스크립트로 커널 기동 시 InfluxDB Connection 객체를 만들어 전역 Namespace에 등록하여, Notebook에서 별도 연결 코드 없이 데이터를 조회할 수 있도록 구성
- DB Endpoint와 인증 정보를 `.ini` 설정으로 외부화하여 Notebook에서 접속 정보를 제거하고, 환경별 설정 변경과 Connection 관리를 공통 영역에서 수행하도록 표준화

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- Notebook을 열면 InfluxDB 연결이 이미 되어 있어서, 셀마다 접속 코드를 붙이지 않음
- 주소와 계정은 `.ini`에만 있어서 Notebook 안에 접속 정보가 들어가지 않음

</div>

## 브라우저 멀티탭 인증 상태 동기화 구조 설계

<div class="ts-block ts-issue" markdown="1">

### 문제

- 같은 브라우저에서 여러 탭을 동시에 쓸 때 로그인·로그아웃·인증 만료 상태가 탭마다 따로 관리되어, 사용자 인증 상태가 서로 다르게 유지됨

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 탭마다 인증 상태를 따로 판단하던 방식 대신, **탭 간 이벤트 기반 세션 동기화 구조로 재설계**
- `BroadcastChannel API`로 로그인, 로그아웃, 인증 만료 이벤트를 브라우저 안 모든 탭에 전달하여 같은 세션 상태를 유지하도록 구성
- 신규 탭이나 새로고침된 화면이 기존 인증 상태를 알 수 있도록, 초기화 때 다른 탭의 세션 상태를 요청·응답하는 공유 흐름을 구현
- 로그아웃과 인증 만료 시 이벤트를 전체 탭으로 전파하여 특정 탭에 이전 인증 정보가 남지 않도록, 인증 lifecycle을 브라우저 전체에서 일관되게 관리

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 한 탭에서 로그아웃하거나 세션이 만료되면 다른 탭도 같이 풀림
- 새 탭을 열거나 새로고침해도, 이미 로그인된 탭이 있으면 그 로그인 상태를 따라감

</div>

## Nx Monorepo 기반 프론트엔드 공통 아키텍처 및 라이브러리 표준화

<div class="ts-block ts-issue" markdown="1">

### 문제

- 여러 SCADA 애플리케이션에서 인증, 세션 관리, 공통 UI가 각자 구현되어 같은 기능의 중복 개발과 애플리케이션별 구현 편차가 발생

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- **Nx Monorepo를 기준으로 공통 영역과 애플리케이션 영역의 책임을 분리하는 프론트엔드 구조로 재설계**
- 인증, 세션 관리, 공통 UI 등 재사용 기능을 Nx `lib` 단위로 분리하고, 애플리케이션이 필요한 기능을 명시적으로 참조하도록 하여 모듈 간 의존 관계를 정리
- LIPS와 SCADA에서 반복되는 기능을 공통 라이브러리로 모으고, 여러 프로젝트에서 공유하는 기능은 npm Package로 제공
- 애플리케이션 내부 전용 라이브러리와 공용 기능의 배포 범위를 나누고, Nx Workspace 기준으로 공통 라이브러리의 위치와 역할을 정형화

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 인증, 세션, 공통 UI는 앱마다 다시 만들지 않고 Nx `lib`를 가져다 씀
- 그 기능을 고치면 lib 한곳만 수정함
- 앱 안에서만 쓰는 코드와, npm으로 다른 프로젝트에 넘기는 패키지를 나눠 둠

</div>

## SCADA UI/UX 개편 및 프론트엔드 스타일 아키텍처 재정비

<div class="ts-block ts-issue" markdown="1">

### 문제

- SCADA UI/UX 3.0 전면 개편 과정에서 여러 화면과 모듈이 하나의 공통 CSS에 의존
- 스타일을 바꾸면 의도하지 않은 화면까지 영향을 받아 결합도가 높고 유지보수가 어려웠음

</div>

<div class="ts-block ts-fix" markdown="1">

### 해결

- 화면 디자인 변경에 그치지 않고, **공통 스타일과 모듈별 스타일의 책임 범위를 다시 나누는 방향으로 스타일 구조를 재설계**
- 전역으로 둘 색상, Typography, Layout과 개별 화면에서만 쓰는 스타일을 구분하여, 기능·모듈 단위로 독립 관리
- 공통 CSS에 쌓여 있던 화면별 스타일 의존을 단계적으로 제거하여, 한 기능의 UI 변경이 다른 모듈로 번지지 않도록 영향 범위를 모듈 안으로 제한
- 반복되는 UI 요소는 공통 영역에서 맞추고, 개별 기능 스타일은 따로 확장할 수 있도록 관리 기준을 정함

</div>

<div class="ts-block ts-verify" markdown="1">

### 결과

- 한 화면 스타일을 고쳐도 공통 CSS를 타던 다른 화면이 같이 바뀌지 않음
- 색, 글자, 레이아웃은 공통으로 두고, 화면별 스타일은 그 모듈 파일에 둠

</div>


---

[← Projects 목록으로 돌아가기](/projects/)
