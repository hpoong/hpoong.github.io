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
- `_tabs/`: 사이드바 탭 (about, archives, categories, tags)
- `_data/`: 연락처, 공유 설정 등 데이터
  - `_data/portfolio.yml`: About 탭(포트폴리오) 내용. 레이아웃은 `_layouts/portfolio.html`, 스타일은 `_sass/custom/_portfolio.scss`
- `_plugins/`: Jekyll 플러그인
- `assets/`: 이미지 등 정적 리소스
- `tools/`: 로컬 실행/테스트 스크립트

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
