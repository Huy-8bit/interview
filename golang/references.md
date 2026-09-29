# References và version policy

Ưu tiên language spec/public package contract. Runtime source đọc theo tag đã deploy; benchmark luôn ghi toolchain, OS/architecture và flags. Website docs có thể hiển thị release mới hơn toolchain local.

| Chủ đề | Primary source |
|---|---|
| Language / memory | [Go spec](https://go.dev/ref/spec), [memory model](https://go.dev/ref/mem) |
| Runtime / GC | [GC guide](https://go.dev/doc/gc-guide), [Go 1.26 release](https://go.dev/doc/go1.26), [runtime tag1.26.4](https://github.com/golang/go/tree/go1.26.4/src/runtime) |
| Maps / P | [Swiss Tables](https://go.dev/blog/swisstable), [Go 1.25 runtime](https://go.dev/doc/go1.25#runtime) |
| Library | [context](https://pkg.go.dev/context), [sync](https://pkg.go.dev/sync), [http](https://pkg.go.dev/net/http), [sql](https://pkg.go.dev/database/sql) |
| Diagnostics | [diagnostics](https://go.dev/doc/diagnostics), [race detector](https://go.dev/doc/articles/race_detector) |
| PostgreSQL | [Isolation](https://www.postgresql.org/docs/current/transaction-iso.html), [constraints](https://www.postgresql.org/docs/current/ddl-constraints.html) |
| Go DB ecosystem | [pgx](https://pkg.go.dev/github.com/jackc/pgx/v5), [sqlc](https://docs.sqlc.dev/en/stable/) |
| Messaging/cache | [Kafka design](https://kafka.apache.org/41/design/design/), [RabbitMQ confirms](https://www.rabbitmq.com/docs/confirms), [Redis docs](https://redis.io/docs/latest/develop/) |
| RPC/schema | [gRPC concepts](https://grpc.io/docs/what-is-grpc/core-concepts/), [deadlines](https://grpc.io/docs/guides/deadlines/), [Protobuf guides](https://protobuf.dev/programming-guides/) |
| Platform | [Kubernetes pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/), [Docker multi-stage](https://docs.docker.com/build/building/multi-stage/) |
| Telemetry | [OTel concepts](https://opentelemetry.io/docs/concepts/observability-primer/), [Prometheus practices](https://prometheus.io/docs/practices/) |
| Security | [OAuth2 BCP RFC9700](https://www.rfc-editor.org/rfc/rfc9700.html), [JWT BCP RFC8725](https://www.rfc-editor.org/rfc/rfc8725.html), [OWASP cheat sheets](https://cheatsheetseries.owasp.org/) |

Không áp exact internal thresholds/queue sizes/GC colors như public ABI. Sources bổ trợ không thay benchmark workload riêng. Không có benchmark20k RPS, migration 5B hoặc live PostgreSQL/Kafka/Redis/Kubernetes deployment được tuyên bố đã thực thi; các design là bài tập với assumptions và validation gates.
