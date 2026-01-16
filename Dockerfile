FROM 84codes/crystal:latest-alpine AS builder
WORKDIR /build

COPY shard.yml shard.lock* ./
RUN shards install --production

COPY src/ src/

RUN shards build --production --error-trace -Dpreview_mt

FROM alpine:3.20

RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    libgcc \
    gc-dev \
    libevent-dev \
    pcre2-dev

RUN addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup -h /app -s /sbin/nologin

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /build/bin/juicy_fruit /app/juicy_fruit

RUN chmod 500 /app/juicy_fruit

USER appuser

ENV CRYSTAL_ENV=production
ENV PORT=4004

EXPOSE 4004

ENTRYPOINT ["/app/juicy_fruit"]