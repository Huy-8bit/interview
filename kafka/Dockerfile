# One image for every Go service of the lab (each compose service picks its
# binary with `command:`). Building once keeps `docker compose up --build` fast.
FROM golang:1.26-alpine AS build
WORKDIR /src
ENV CGO_ENABLED=0 GOFLAGS=-trimpath
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY pkg ./pkg
COPY services ./services
COPY tools ./tools
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    set -e; mkdir -p /out; \
    for s in producer order-consumer payment-consumer analytics-consumer notification-consumer \
             traffic-generator txn-processor lag-exporter; do \
      go build -ldflags="-s -w" -o /out/$s ./services/$s; \
    done; \
    go build -ldflags="-s -w" -o /out/kcli ./tools/kcli

FROM alpine:3.22
# iproute2/iptables: used by the network fault labs (tc netem / iptables run in a
# broker's network namespace via `docker run --network container:<broker>`).
RUN apk add --no-cache ca-certificates tzdata iproute2 iptables wget bash jq curl
COPY --from=build /out/ /app/
RUN ln -s /app/kcli /usr/local/bin/kcli
USER root
WORKDIR /app
