# AGENTS.md

Cursor, Codex, Claude Code가 공통으로 참조하는 프로젝트 지침입니다.
`CLAUDE.md`는 이 파일의 심볼릭 링크이므로 **이 파일만 수정**하세요.

## 공통 규칙

- 모든 응답은 한국어로 작성합니다.
- 사용자가 명시적으로 요청하기 전에는 커밋/푸시하지 않습니다.

## 프로젝트 개요

- GitHub Pages 개인 블로그 (`hpoong.github.io`)
- [Jekyll](https://jekyllrb.com/) + [Chirpy 테마](https://github.com/cotes2020/jekyll-theme-chirpy) (`jekyll-theme-chirpy ~> 7.6`, gem 방식)
- `main` 브랜치 푸시 시 `.github/workflows/pages-deploy.yml`로 빌드/배포

## 디렉터리 구조

- `_config.yml`: 사이트 설정 (제목, URL, 언어, 댓글 등)
- `_posts/`: 블로그 글 (`YYYY-MM-DD-title.md`)
- `_tabs/`: 사이드바 탭 (categories, projects, about)
  - Archives/Tags 탭은 제거. `/tags/` 페이지는 태그 상세의 breadcrumb용으로 루트 `tags.md`에서 유지
- `_data/`: 연락처, 공유 설정 등 데이터
  - `_data/portfolio.yml`: About 탭(경력, 프로젝트 목록)과 Projects 탭(대표 프로젝트 카드) 내용
- `_layouts/portfolio.html`: About 탭 레이아웃. 스타일은 `_sass/custom/_portfolio.scss`
- `_includes/portfolio-*.html`: 포트폴리오 공용 조각 (Projects 카드, PAAR, 배지, 링크)
- `projects/{id}.md`: 대표 프로젝트 상세 페이지 (`/projects/{id}/`)
- `_plugins/`: Jekyll 플러그인
- `assets/`: 이미지 등 정적 리소스
- `tools/`: 로컬 실행/테스트 스크립트

## 포트폴리오 관리

- 대표 프로젝트 추가: `_data/portfolio.yml`의 `projects`에 `id`로 카드를 추가하고, 같은 `id`로 `projects/{id}.md` 상세 페이지를 작성
- About 경력의 `experience[].projects[].featured`에 `id`를 넣으면 목록에 상세 버튼(새 창)이 붙고, 소개는 `projects`의 `summary`를 사용
- `_config.yml`, `sitemap.xml`처럼 시작 시 읽는 파일을 바꾸면 로컬 서버 재시작 필요 (`docker restart hpoong-blog`)

## 검색 비공개 설정

검색 엔진·AI 봇에 노출되지 않도록 아래 설정을 유지합니다. 새 페이지를 추가해도 자동 적용됩니다.

- `_includes/metadata-hook.html`: 모든 페이지에 `noindex, nofollow` 메타 태그
- `assets/robots.txt`: AI 크롤러 차단 (`*`는 noindex를 읽을 수 있도록 허용)
- `sitemap.xml`: 빈 sitemap으로 jekyll-sitemap 자동 생성을 대체
- `assets/feed.xml`: 글 목록이 없는 빈 피드로 테마 기본 Atom 피드를 대체 (사이드바 RSS 아이콘도 `_data/contact.yml`에서 제거)
- 저장소가 공개 상태이므로 실명 등 민감한 정보는 소스에 커밋하지 않습니다.

## 명령어

```bash
bundle install          # 의존성 설치
bash tools/run.sh       # 로컬 서버 (http://127.0.0.1:4000)
bash tools/test.sh      # 프로덕션 빌드 + html-proofer 검사

# 로컬 Ruby 없이 Docker로 실행
docker compose up --build   # http://localhost:4000
```

## 글 작성 규칙

- 파일명: `_posts/YYYY-MM-DD-slug.md`
- Front matter 예시:

```yaml
---
title: 글 제목
date: 2026-10-03 22:00:00 +0900
categories: [대분류, 소분류]
tags: [tag1, tag2]
---
```

- 이미지는 `assets/img/posts/` 아래에 두고 절대 경로(`/assets/img/...`)로 참조합니다.
- `tags`는 소문자를 사용합니다.
