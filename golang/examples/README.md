# Runnable Go labs

Module dùng Go language baseline 1.23; đã thiết kế để test bằng Go 1.26.4 trong workspace. Không có third-party dependencies. HTTP tests mở loopback listener; chạy trong môi trường cho phép bind local port. SQL functions compile nhưng cần driver/PostgreSQL thật để kiểm integration behavior; repository không giả lập kết quả DB benchmark.

Từ `golang/examples`:

```bash
go test ./...
go test -race ./...
go vet ./...
go test -run '^$' -bench BenchmarkFormat -benchmem -count=10
go test -run '^$' -fuzz FuzzLowerBound -fuzztime=5s
go test -run '^$' -fuzz FuzzDecimalRoundTrip -fuzztime=5s
go test -run TestPoolCancellation -trace=trace.out
go tool trace trace.out
go run ./cmd/server
```

| Code | Contract / verification |
|---|---|
| [pool.go](pool.go) | Fixed workers, fail-fast cancellation, join; caller owns input, fn honors ctx |
| [pool_test.go](pool_test.go) | Completion, cancellation, worker error, invalid limit |
| [http.go](http.go) | Shared Transport, bounded body, status errors và cleanup |
| [http_test.go](http_test.go) | Real HTTP/1 reuse, body limit, canceled request |
| [sql.go](sql.go) | Rows Close/Err và transaction cleanup; real DB setup chưa bao gồm |
| [algorithms.go](algorithms.go) | Map/list/queue/tree/graph/heap/search/window/pointers |
| [algorithms_test.go](algorithms_test.go) | Edge cases, queue ownership và fuzz partition invariant |
| [benchmark_test.go](benchmark_test.go) | Benchmark harness và numeric round-trip fuzz |
| [cmd/server/main.go](cmd/server/main.go) | Runnable server và bounded SIGTERM shutdown |

## Negative race demonstration

[Intentional race](race_demo_test.go) bị loại khỏi default suite bằng build tag. Lệnh sau **phải thất bại** với DATA RACE; không dùng tag này trong suite pass:

```bash
go test -race -tags racedemo -run TestIntentionalRace
```

## Lab scope

Pool in-process không durable; producer cần stop khi pool return. Integer TwoSum examples giả định arithmetic không overflow; byte sliding-window không là grapheme algorithm. Server sample chỉ health endpoint; production DB/consumer wiring có documented close order nhưng không giả vờ chứa dependencies chưa cấu hình.

[Dashboard](../README.md) · [Audit](../00-roadmap/repository-audit.md)
