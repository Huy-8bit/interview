# Lập trình concurrency với lifecycle rõ ràng

## Bài toán và ví dụ đầu tiên

Bài viết worker pool thường dễ pass happy path nhưng treo khi consumer bỏ cuộc. Coding concurrency cần contract lifecycle trước syntax: số worker, bound queue, lỗi đầu, cancellation và ai chờ hoàn tất.

## Đi từng bước qua một tình huống

Vẽ producer→jobs→workers→result owner. Producer close jobs khi không còn gửi; coordinator chờ mọi sender trước close result. Mỗi send/receive có thể block phải có đường tiến triển hoặc cancel. Callback được truyền ctx nhưng phải thực sự dùng nó.

## Hiểu cơ chế từ kết quả quan sát

Chọn result/error protocol để owner không return bỏ workers vô chủ. Channel buffer một phần tử hợp lý cho một lỗi đầu, không là queue vô hạn chứa mọi lỗi. Shared counters trong tests vẫn cần atomic/lock, và go statement không tự copy sâu payload.

Đúng concurrency gồm results, cancellation, bounded resource use và termination proof.

## Cơ chế và những ranh giới cần giữ

Thiết kế owners cho input/output/close; Add trước launch, context ở mọi blocking operation, join trước return. Error policy fail-fast hay best-effort phải nói rõ.

## Áp dụng vào hệ thống thật

Implement bounded worker pool có worker error và caller cancel như examples/pool.go.

## Những đường lỗi cần hiểu

Hidden leak khi result reader exit; close chung từ nhiều workers; spawn trước acquire vô hạn waiters.

## Lần theo bằng chứng khi có sự cố

Test completion counts, bound active workers, first error cancellation và no active worker khi return.

## Đánh đổi và giới hạn sử dụng

Synchronous baseline nếu không cần parallel; đừng tối ưu scheduling trước correctness.

## Thực hành, debugging và kết luận

Đọc RunPool trong examples và tests điều phối bằng started/finished channels. Thử cancel trước start, worker lỗi và caller dừng receive. Không dùng Sleep để bảo đảm lịch chạy; timeout chỉ làm test thất bại có giới hạn nếu protocol bị treo.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Runnable solution

[Worker pool và tests](../examples/pool.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
