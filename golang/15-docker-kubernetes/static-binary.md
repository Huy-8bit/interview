# Static binaries và cgo

## Bài toán và ví dụ đầu tiên

Một binary copy sang image tối giản báo lỗi không chạy hoặc TLS fail. “Một file binary” không luôn nghĩa không có dependency runtime: dynamic libraries, CA roots, timezone và config còn phụ thuộc cách build và code dùng.

## Đi từng bước qua một tình huống

Build thuần Go với cgo tắt phù hợp nhiều service nhưng một số thư viện cần native linking. GOOS/GOARCH quyết định target, không thể chạy binary kiến trúc khác trực tiếp. Kiểm tra file/linking của artifact thay vì suy từ tên đuôi file.

## Hiểu cơ chế từ kết quả quan sát

Static linking giảm phụ thuộc shared libraries nhưng không nhúng mặc nhiên mọi dữ liệu hệ thống. DNS behavior có thể khác theo resolver/build/environment. Certificate verification cần trust store hoặc cấu hình rõ, không được tắt TLS verify chỉ để image nhỏ chạy được.

## Khái niệm và mô hình làm việc

Go binary có thể tự chứa nhiều runtime support, nhưng static linkage phụ thuộc build/dependencies.

## Cơ chế và những ranh giới cần giữ

CGO_ENABLED=0 cho pure-Go-compatible build thường tránh libc dynamic deps; cgo libraries có thể cần native runtime. DNS/user lookup behavior có thể khác.

## Áp dụng vào hệ thống thật

Cross-compile linux/arm64 cho platform deployment, test target image thực.

## Những đường lỗi cần hiểu

Giả định mọi Go binary static; executable not found do missing dynamic loader dù file tồn tại.

## Lần theo bằng chứng khi có sự cố

Inspect binary format/linkage trên đúng OS; compare DNS/TLS behavior trong image.

## Đánh đổi và giới hạn sử dụng

Disable cgo không là universal optimization; dependency/native performance có thể cần cgo.

## Thực hành, debugging và kết luận

Test trong đúng base image, user và network environment mục tiêu. Ghi build flags và toolchain. Chọn static khi portability phù hợp, giữ cgo khi cần chức năng/performance đã đo và đóng gói dependency native có chủ đích.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kubernetes.io/docs/concepts/)
