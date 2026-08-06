FROM ruby:4.0.6-alpine AS builder
RUN apk add --no-cache build-base postgresql-dev

WORKDIR /power-splitter
COPY Gemfile* /power-splitter/
# The precompiled musl build of pg carries its own libpq with OpenSSL and krb5
# linked in statically - six times the size of the one built here against the
# 350 KB libpq of Alpine. Building it costs seconds of CI; shipping it costs
# every user megabytes on every pull. Hence no precompiled gems, and hence no
# musl platforms in Gemfile.lock: they would never be used.
RUN bundle config --local frozen 1 && \
    bundle config --local without 'development test' && \
    bundle config --local force_ruby_platform true && \
    bundle install -j4 --retry 3 && \
    bundle clean --force && \
    rm -rf /usr/local/bundle/cache

FROM ruby:4.0.6-alpine
LABEL org.opencontainers.image.authors="georg@ledermann.dev"
LABEL org.opencontainers.image.description="Distributes imported grid power among individual consumers"

# Add tzdata to get correct timezone
RUN apk add --no-cache tzdata libpq

# Decrease memory usage
ENV MALLOC_ARENA_MAX=2

# The Alpine build ships YJIT but leaves it switched off, and splitting a day is
# the kind of arithmetic in a tight loop it is good at: measured against this
# image, a day of 1440 records went from 157 ms to 105 ms. A worker that runs
# for weeks pays the warmup once, and RSS grows by about 3 MB.
ENV RUBY_YJIT_ENABLE=1

# Move build arguments to environment variables
ARG BUILDTIME
ENV BUILDTIME=${BUILDTIME}

ARG VERSION
ENV VERSION=${VERSION}

ARG REVISION
ENV REVISION=${REVISION}

# Git-describe version (e.g. v0.10.1-3-g2d8f177), which - unlike VERSION -
# is a real version on branch builds, too. Used by HELIOS to show the version.
ARG COMMIT_VERSION
ENV COMMIT_VERSION=${COMMIT_VERSION}

WORKDIR /power-splitter

COPY --from=builder /usr/local/bundle/ /usr/local/bundle/
COPY . /power-splitter/

ENTRYPOINT ["bundle", "exec", "app.rb"]
