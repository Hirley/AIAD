# syntax=docker/dockerfile:1

# Estágio de build: compila as gems nativas e não vai para a imagem final.
FROM ruby:4.0-slim AS build

RUN apt-get update -qq \
    && apt-get install --no-install-recommends -y build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=test

COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf "${BUNDLE_PATH}"/cache

# Imagem final: sem compilador, sem gems de teste e sem rodar como root.
FROM ruby:4.0-slim AS runtime

RUN useradd --create-home --shell /usr/sbin/nologin aiad

WORKDIR /app

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=test \
    RACK_ENV=production \
    PORT=9292 \
    QDRANT_URL=http://qdrant:6333

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=aiad:aiad Gemfile Gemfile.lock config.ru ./
COPY --chown=aiad:aiad config ./config
COPY --chown=aiad:aiad lib ./lib

USER aiad

EXPOSE 9292

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ruby -e "require 'net/http'; exit(Net::HTTP.get_response(URI(\"http://127.0.0.1:#{ENV['PORT']}/health\")).code == '200' ? 0 : 1)"

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb", "config.ru"]
