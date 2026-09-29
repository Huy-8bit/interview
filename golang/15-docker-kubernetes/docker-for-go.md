# Docker cho Go services

## Bài toán và ví dụ đầu tiên

Team muốn build Go service giống nhau ở CI và production. Dockerfile mô tả môi trường build/runtime, nhưng reproducibility còn phụ thuộc module graph, toolchain và base image được chọn.

## Đi từng bước qua một tình huống

Stage build tải dependencies từ go.mod/go.sum rồi compile target GOOS/GOARCH. Runtime stage chỉ nhận binary và assets cần. Copy dependency manifests trước source có thể giúp cache build, nhưng không thay kiểm tra checksums và build output đúng commit.

## Hiểu cơ chế từ kết quả quan sát

CGO_ENABLED=0 có thể tạo binary ít dependency native hơn cho nhiều ứng dụng, nhưng không áp dụng nếu driver/library cần cgo. CA certificates, config và migrations vẫn có thể là runtime requirements. Secrets dùng build không nên trở thành layer/image history.

## Khái niệm và mô hình làm việc

Image đóng gói binary và runtime dependencies; container chia kernel với host, không phải VM riêng.

## Cơ chế và những ranh giới cần giữ

Build reproducible bằng pinned toolchain/dependency checksums, non-root runtime user, exec-form ENTRYPOINT để signals tới process.

## Áp dụng vào hệ thống thật

Một image API/worker dùng cùng source commit; inject config/secrets lúc deploy.

## Những đường lỗi cần hiểu

Missing CA certificates làm HTTPS fail; shell PID1 nuốt signals; timezone/native libs thiếu.

## Lần theo bằng chứng khi có sự cố

Inspect image metadata, UID, binary linkage và logs khi SIGTERM; smoke test outbound TLS.

## Đánh đổi và giới hạn sử dụng

Minimal image giảm surface nhưng debug khó; giữ debug tooling qua workflow riêng.

## Thực hành, debugging và kết luận

Chạy container smoke/integration tests với non-root user, health endpoint và SIGTERM. Ghi version/build metadata để incident biết binary nào. Image build thành công chưa chứng minh query, DNS hoặc TLS hoạt động trong runtime filesystem tối giản.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://docs.docker.com/guides/golang/)
