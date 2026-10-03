# 로컬 미리보기용 Jekyll 이미지 (배포는 GitHub Actions가 담당)
FROM ruby:3.4-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/jekyll

COPY Gemfile ./
RUN bundle install

EXPOSE 4000 35729

# --force_polling: macOS 볼륨 마운트에서 파일 변경 감지가 누락되지 않도록
CMD ["bundle", "exec", "jekyll", "serve", "--host", "0.0.0.0", "--livereload", "--force_polling"]
