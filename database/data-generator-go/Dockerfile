FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /generator .

FROM alpine:3.23
RUN apk add --no-cache ca-certificates
COPY --from=build /generator /usr/local/bin/generate-data-go
USER 65534:65534
ENTRYPOINT ["generate-data-go"]
