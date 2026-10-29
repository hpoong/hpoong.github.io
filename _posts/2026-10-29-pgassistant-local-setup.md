---
title: AI로 DB 튜닝하기 (2) - pgAssistant를 에이전트에 연결하기
date: 2026-10-29 10:00:00 +0900
categories: [AI, DB 튜닝]
tags: [ai-agent, cursor, claude-code, codex, postgresql, pg-stat-statements, pgassistant, docker]
---

## 도입 배경

코드 작성은 이미 AI 에이전트와 함께 하고 있다. Cursor, Claude Code, Codex 같은 에이전트에 기능 구현이나 리팩터링을 맡기는 일이 일상이 됐다. 그런데 **DB 튜닝은 여전히 사람이 직접** 하고 있었다.

MES는 MyBatis 매퍼에 SQL을 직접 작성한다. 쿼리를 튜닝하려면 다음 과정을 거친다.

- **부하가 큰 쿼리 찾기:** `pg_stat_statements`를 조회하고 정렬해서 본다.
- **소스 연결:** 정규화된 SQL 문자열을 보고 매퍼 XML을 검색한다.
- **원인 분석:** `EXPLAIN`을 돌리고 기존 인덱스를 하나씩 확인한다.
- **개선안 검증:** 수정한 쿼리가 같은 결과를 내는지, 실제로 빨라졌는지 다시 확인한다.

이 중 상당 부분은 에이전트가 더 잘할 수 있는 일이다. 수많은 매퍼에서 SQL을 찾아 연결하고, 수정안을 만들고, 전후를 비교하는 일은 사람보다 빠르고 빠뜨리는 것도 적다.

문제는 에이전트가 **소스는 잘 읽어도 DB 상태는 모른다**는 점이다. 어떤 쿼리가 실제로 부하가 큰지, 어떤 인덱스가 있는지 알려줄 수단이 필요했다. 문제가 터진 뒤에 대응하는 것이 아니라, **에이전트가 DB 상태를 근거로 미리 튜닝**하도록 만드는 것이 목표다.

## 해결 방향: pgAssistant

**pgAssistant**는 PostgreSQL을 분석해 주는 오픈소스 도구다. 웹 화면에서 DB 상태와 쿼리 통계를 볼 수 있고, **API v2**로 같은 분석을 호출할 수 있다.

핵심은 `executive-plan` API다. DB 연결 문자열을 넘기면 **개선 계획과 제안 SQL**을 돌려준다. 제안 SQL을 직접 적용하지는 않는다. 분석만 하고, 판단과 적용은 사람이 한다.

역할은 다음처럼 나눴다.

| 구성 요소 | 역할 |
| --- | --- |
| pgAssistant | DB 전체를 분석해 개선 계획과 제안 SQL을 반환 |
| 에이전트 (Cursor / Claude Code / Codex 등) | API 결과를 MES 매퍼에 연결하고 수정안 작성 |
| PostgreSQL MCP | 개별 SQL 조회, 실행 계획, 성능 검증 |

## 구성 방법

### 1. 기존 DB에 붙이기만 한다

Compose에는 pgAssistant 컨테이너 **하나만** 둔다. PostgreSQL이나 에이전트는 포함하지 않는다. 이미 쓰고 있는 개발 DB에 연결해서 분석만 한다.

```yaml
services:
  pgassistant:
    image: bertrand73/pgassistant:${PGASSISTANT_TAG:-latest}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${PGASSISTANT_PORT:-8080}:5005"
    environment:
      SECRET_KEY: ${SECRET_KEY:?Set SECRET_KEY in .env}
      PGA_API_TOKEN: ${PGA_API_TOKEN:?Set PGA_API_TOKEN in .env}
```

Compose는 기존 DB의 설정이나 확장을 **변경하지 않는다.**

### 2. 현재 PC에서만 연다

포트를 `127.0.0.1`에만 바인딩했다. `8080:5005`로 쓰면 같은 네트워크의 다른 PC에서도 접근할 수 있다. DB 접속 정보를 다루는 도구라서 **로컬에서만 열리도록** 했다.

### 3. 비밀값은 `.env`로 분리한다

세션 키(`SECRET_KEY`)와 API 토큰(`PGA_API_TOKEN`)은 `.env`에 둔다. Compose에서 `${VAR:?메시지}` 형태로 참조해서, **값이 없으면 컨테이너가 아예 뜨지 않게** 했다. 기본값으로 조용히 실행되는 일을 막기 위해서다.

### 4. DB 주소는 컨테이너 기준으로 쓴다

연결 문자열은 다음 형식이다.

```text
postgresql://USER:PASSWORD@DB_HOST:5432/DB_NAME
```

여기서 실수하기 쉬운 부분이 `DB_HOST`다. pgAssistant는 **컨테이너 안에서** DB에 접속하므로, 컨테이너 기준으로 접근 가능한 주소를 써야 한다. `localhost`를 쓰면 컨테이너 자기 자신을 가리킨다.

| DB 위치 | DB_HOST |
| --- | --- |
| Windows PC에서 실행 중인 DB | `host.docker.internal` |
| 별도 개발 서버의 DB | 해당 서버의 호스트명 또는 IP |
| 다른 컨테이너의 DB | Windows에 공개된 포트로 접근하거나 Docker 네트워크 연결 |

### 5. `pg_stat_statements`를 먼저 확인한다

실행 통계 기반 분석을 하려면 대상 DB에 `pg_stat_statements`가 활성화되어 있고, 통계를 조회할 권한이 있어야 한다. 기존 SQL 도구에서 먼저 확인한다.

```sql
SHOW shared_preload_libraries;
SELECT extname FROM pg_extension WHERE extname = 'pg_stat_statements';
```

확장이 없으면 서버 설정과 확장 설치를 별도로 진행해야 한다. 일부 분석은 확장 없이도 동작한다. 계정은 처음부터 **분석에 필요한 권한만 가진 계정**으로 시작했다.

활성화 방법과 권한, 통계를 읽는 법은 [AI로 DB 튜닝하기 (1) - pg_stat_statements로 튜닝 대상 찾기](/posts/pg-stat-statements/)에 정리했다.

### 6. 에이전트는 API를 호출한다

Compose를 띄운다고 에이전트가 자동으로 연결되지는 않는다. 에이전트가 HTTP 호출 도구나 스크립트로 API를 부르도록 한다.

```text
POST http://localhost:8080/api/v2/executive-plan
Authorization: Bearer <.env의 PGA_API_TOKEN>
Content-Type: application/json

{"database_uri":"postgresql://USER:PASSWORD@DB_HOST:5432/DB_NAME"}
```

`database_uri`도 4번과 같은 이유로 **컨테이너에서 접근 가능한 주소**여야 한다.
pgAssistant에는 내부 LLM 기능도 있지만 선택 사항이다. 외부 에이전트가 분석 API를 쓰는 데는 **내부 LLM 설정이 필요 없다.**

## 실행

```bash
docker compose up -d
```

`http://localhost:8080`으로 웹 화면에, `http://localhost:8080/api/v2/docs`로 API 문서(Swagger)에 접속한다.

## 에이전트에게 맡기기

MES 소스를 연 에이전트에게 이렇게 지시했다.

> pgAssistant API로 개발 DB를 분석하고, 부하가 큰 SELECT를 MES MyBatis 매퍼에 연결해 줘. 기존 인덱스와 실행 계획을 확인하고 쿼리 수정안을 만들어 결과 동일성과 성능을 검증해 줘. 개발 DB 대상임을 먼저 확인하고, DB 변경 SQL은 적용하지 말고 제안과 근거를 보고해 줘.

지시에 넣은 제약은 세 가지다.

- **개발 DB인지 먼저 확인한다.** 연결 문자열을 잘못 넘기는 실수를 막는다.
- **DB 변경 SQL은 적용하지 않는다.** 인덱스 생성 같은 제안은 근거와 함께 보고만 받는다.
- **결과 동일성을 검증한다.** 빨라졌어도 결과가 달라지면 의미가 없다.

## 처리 흐름

```text
[에이전트]
├─ 1. 대상이 개발 DB인지 확인
├─ 2. pgAssistant executive-plan API 호출
│    └─ 개선 계획 + 제안 SQL 수신 (DB에는 적용되지 않음)
├─ 3. 부하가 큰 SELECT를 MES MyBatis 매퍼에서 검색
├─ 4. PostgreSQL MCP로 기존 인덱스·실행 계획 확인
├─ 5. 쿼리 수정안 작성
├─ 6. 수정 전/후 결과 동일성 비교
├─ 7. 수정 전/후 실행 계획·성능 비교
└─ 8. 제안과 근거 보고 → 적용 여부는 사람이 판단
```

## 정리

- pgAssistant는 **기존 개발 DB에 붙여서 분석만** 한다. Compose에는 pgAssistant 하나만 둔다.
- 포트는 **`127.0.0.1`에만** 열고, 비밀값은 `.env`로 분리해 **없으면 실행되지 않게** 했다.
- DB 주소는 **컨테이너 기준**으로 쓴다. 로컬 DB는 `host.docker.internal`이다.
- 실행 통계 분석에는 **`pg_stat_statements`**가 필요하다.
- 에이전트는 **API로 분석 결과를 받고**, MCP로 개별 검증을 이어간다. DB 변경은 제안까지만 한다.

> API 토큰은 DB 연결 문자열을 받는 API의 열쇠다. 채팅, 저장소, 에이전트 지시문에 직접 넣지 않는다.
{: .prompt-warning }

## 참고

- [pgAssistant Docker 설치](https://beh74.github.io/pgassistant-blog/doc/startup_docker/)
- [pgAssistant API v2](https://github.com/beh74/pgassistant-community/blob/main/docs/api-v2.md)
- [pgAssistant Community](https://github.com/beh74/pgassistant-community)
