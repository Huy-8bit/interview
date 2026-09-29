# Stack và queue bằng slices

## Bài toán và ví dụ đầu tiên

Stack lấy phần tử mới thêm gần nhất; queue lấy phần tử chờ lâu nhất. Cả hai có thể dùng slice, nhưng queue pop đầu bằng copy mọi phần tử mỗi lần làm work tăng, còn chỉ tăng head có thể giữ references đã dùng.

## Đi từng bước qua một tình huống

Lab Queue giữ data và head. Pop lấy data[head], gán zero vào ô đó để bỏ reference, rồi tăng head. Khi hết queue, reset slice/head. Khi prefix đã lớn và chiếm nhiều buffer, compact phần còn lại để không giữ backing array vô ích mãi.

## Hiểu cơ chế từ kết quả quan sát

Gán zero quan trọng với pointer/slice/map values vì ô cũ còn tham chiếu object nếu chỉ tăng head. Compaction có chi phí copy nhưng amortized theo nhiều operations khi threshold hợp lý. Queue generic này không thread-safe; concurrent Push/Pop cần owner hoặc synchronization bên ngoài.

## Khái niệm và mô hình làm việc

Stack LIFO dùng append/pop cuối; queue FIFO cần tránh dịch toàn slice mỗi Pop.

## Cơ chế và những ranh giới cần giữ

Queue có head index, clear slot đã lấy để bỏ references; compact khi consumed prefix lớn, reset khi empty. Amortized O(1), occasional copy.

## Áp dụng vào hệ thống thật

BFS queue hoặc local bounded scheduler; concurrency cần mutex/channel tùy ownership.

## Những đường lỗi cần hiểu

Pop bằng s=s[1:] giữ giant array; không clear pointer slot giữ objects; concurrent accesses race.

## Lần theo bằng chứng khi có sự cố

Test order qua compaction, empty pop và storage release sau drain.

## Đánh đổi và giới hạn sử dụng

Ring buffer tốt cho fixed bound; dynamic slice queue linh hoạt nhưng cần memory policy.

## Thực hành, debugging và kết luận

Test FIFO, empty pop, reuse sau drain và payload references được xóa theo semantics. Với bounded queue production, thêm cap và overload policy thay vì append vô hạn. Chọn ring buffer nếu cần bound/latency predictable theo workload, đo trước khi làm implementation phức tạp.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Runnable solution

[Algorithms implementation](../examples/algorithms.go) và [edge-case/property tests](../examples/algorithms_test.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
