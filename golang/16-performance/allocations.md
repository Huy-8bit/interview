# Allocation optimization

## Bài toán và ví dụ đầu tiên

Hot path chuyển string sang []byte, format log và tạo slices tạm mỗi request. Tổng live heap có thể không lớn nhưng allocation rate tăng làm allocator/GC tốn CPU. Tối ưu allocation phải biết object nào được tạo nhiều và sống bao lâu.

## Đi từng bước qua một tình huống

Benchmark với -benchmem cho B/op và allocs/op, profile alloc_space cho cumulative bytes. Preallocate slice nếu biết bound có thể giảm growth, nhưng overallocate lớn giữ memory dư. Reuse buffer chỉ đúng khi không còn consumer giữ view của lần dùng trước.

## Hiểu cơ chế từ kết quả quan sát

Escape analysis giải thích placement của compiler tại build cụ thể; không phải mọi interface hay pointer đều allocate. Pool có thể giảm churn nhưng runtime được phép bỏ entries và object trả về cần reset references đúng. Buffer lớn bất thường cần size policy để pool không giữ peak vô ích.

## Khái niệm và mô hình làm việc

Allocation rate tạo allocator/GC work; tối ưu ownership và buffer sizing trước unsafe tricks.

## Cơ chế và những ranh giới cần giữ

Preallocate measured size, reuse bounded buffers với clear owner, avoid repeated conversions; sync.Pool contents có thể bị bỏ bất kỳ GC cycle.

## Áp dụng vào hệ thống thật

JSON batching giảm per-item overhead nếu latency/memory budget cho phép.

## Những đường lỗi cần hiểu

Pool oversized buffer giữ RAM; concurrent reuse corrupt data; global sink làm benchmark escape giả.

## Lần theo bằng chứng khi có sự cố

benchmem plus alloc_space và inuse_space; inspect compiler -m=2 sau xác định hotspot.

## Đánh đổi và giới hạn sử dụng

Clone tăng alloc nhưng có thể giảm live heap; không tối ưu alloc count tách bytes/lifetime.

## Thực hành, debugging và kết luận

Xác nhận allocation giảm ở workload representative và output đúng với aliasing/concurrency tests. Đo GC CPU và P99 cùng memory vì ít allocation không luôn nhanh hơn nếu thêm lock/copy đắt. Tránh tối ưu nơi profile cho thấy chi phí không đáng kể.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](pprof.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
