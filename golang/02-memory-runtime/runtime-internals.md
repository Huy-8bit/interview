# Runtime internals: ranh giới contract

## Bài toán và ví dụ đầu tiên

Một bài viết cũ vẽ map bằng bucket, trong khi binary đang deploy dùng implementation mới. Kiến thức source rất hữu ích để debug nhưng phải tách contract ổn định khỏi thuật toán của một phiên bản cụ thể.

## Đi từng bước qua một tình huống

Language specification trả lời chương trình được phép dựa vào hành vi nào. Package docs mô tả contract API như Mutex hoặc Context. Source theo tag giải thích contract được thực hiện thế nào trong build đó. Đọc proc.go cho scheduler, chan.go cho channel và vùng runtime/maps tương ứng khi tìm map implementation.

## Hiểu cơ chế từ kết quả quan sát

Tên field, kích thước queue, thresholds và debug flags có thể đổi. Một optimization của compiler còn phụ thuộc kiến trúc và build flags. Ghi go version, GOOS/GOARCH, race/cgo flags, GOMAXPROCS và CPU quota giúp người khác tái hiện đúng môi trường trước khi suy luận từ trace.

## Khái niệm và mô hình làm việc

Language spec và public package docs là contract; runtime source giải thích implementation cụ thể.

## Cơ chế và những ranh giới cần giữ

Đọc proc.go, chan.go, mgc.go và internal/runtime/maps theo tag Go đang deploy. Compiler flags và GODEBUG cũng có lifecycle/version.

## Áp dụng vào hệ thống thật

Incident note ghi go version, GOOS/GOARCH, build flags, GOMAXPROCS và container quota.

## Những đường lỗi cần hiểu

Dùng bucket diagram cũ cho Swiss Tables; khẳng định queue size bất biến; tune flag đã đổi behavior.

## Lần theo bằng chứng khi có sự cố

Tái hiện trên đúng binary/toolchain; đối chiếu release notes và source tag trước diễn giải trace.

## Đánh đổi và giới hạn sử dụng

Biết internals để đặt giả thuyết, không phụ thuộc ABI/private struct bằng unsafe trong business code.

## Thực hành, debugging và kết luận

Khi một nâng cấp Go thay performance, giữ application/workload cố định rồi so hai toolchain. Đọc release note chính thức và profile trên binary tương ứng. Không copy một tuning flag từ incident khác khi chưa xác minh nó còn tồn tại và giải quyết đúng symptom.


## Đọc tiếp

- [Garbage collection: live heap, pacing và memory budget](garbage-collector.md)
- [Escape analysis: đọc quyết định của compiler](escape-analysis.md)
- [memory-profile](../16-performance/memory-profile.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/gc-guide)
