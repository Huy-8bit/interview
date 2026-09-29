# Multi-stage builds

## Bài toán và ví dụ đầu tiên

Image chứa compiler và source dù production chỉ cần chạy binary, làm artifact lớn và thêm phần mềm không cần. Multi-stage build tách môi trường compile khỏi môi trường runtime.

## Đi từng bước qua một tình huống

Builder có Go toolchain, module cache và source; lệnh build tạo binary. Final stage copy binary và chỉ những assets cần như CA bundle. Paths/config phải khớp working directory runtime, không dựa file còn sót từ builder.

## Hiểu cơ chế từ kết quả quan sát

Tách stage không tự đảm bảo reproducibility hay security: base images/toolchain/dependency version vẫn cần pin theo policy và cập nhật có kiểm thử. Cgo binary có thể cần shared libraries, còn static binary vẫn cần network trust roots nếu gọi HTTPS.

## Khái niệm và mô hình làm việc

Build stage chứa compiler; runtime stage chỉ chứa binary và assets cần thiết.

## Cơ chế và những ranh giới cần giữ

Copy go.mod/go.sum trước để cache dependencies; build target GOOS/GOARCH rõ; pin base image digest trong deployment workflow thực.

## Áp dụng vào hệ thống thật

Pure Go service compile trong builder rồi copy binary + CA certs vào minimal runtime.

## Những đường lỗi cần hiểu

Cache layer giữ secrets do COPY; architecture mismatch; builder libs thiếu runtime khi cgo.

## Lần theo bằng chứng khi có sự cố

docker history/image inspect, file/ldd tương ứng platform, run non-root smoke test.

## Đánh đổi và giới hạn sử dụng

Không đưa token vào ARG/layer; dùng build secret mechanism khi private modules cần credentials.

## Thực hành, debugging và kết luận

Inspect runtime contents và chạy endpoint/dependency TLS test trong image. So size và startup nhưng không bỏ debug metadata cần symbolization của profiles một cách vô thức. Giữ source/binary version mapping ngoài image để vận hành điều tra được.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://docs.docker.com/build/building/multi-stage/)
