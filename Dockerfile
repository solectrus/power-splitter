FROM ruby:3.3.5-alpine AS builder
RUN apk add --no-cache build-base

WORKDIR /power-splitter
COPY Gemfile* /power-splitter/
RUN bundle config --local frozen 1 && \
    bundle config --local without 'development test' && \
    bundle install -j4 --retry 3 && \
    bundle clean --force

FROM ruby:3.3.5-alpine
LABEL org.opencontainers.image.authors="georg@ledermann.dev"
LABEL org.opencontainers.image.description="Distributes imported grid power among individual consumers"

# Add tzdata to get correct timezone
RUN apk add --no-cache tzdata

# Decrease memory usage
ENV MALLOC_ARENA_MAX=2

# Move build arguments to environment variables
ARG BUILDTIME
ENV BUILDTIME=${BUILDTIME}

ARG VERSION
ENV VERSION=${VERSION}

ARG REVISION
ENV REVISION=${REVISION}

WORKDIR /power-splitter

COPY --from=builder /usr/local/bundle/ /usr/local/bundle/
COPY . /power-splitter/

ENTRYPOINT ["bundle", "exec", "app.rb"]
