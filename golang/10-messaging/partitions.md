# Partitions: ordering và scale unit

## Bài toán và ví dụ đầu tiên

Một topic có nhiều partitions để phân phối storage và xử lý. Mỗi partition là một log có thứ tự riêng; key routing quyết định những events nào cần đi cùng một hàng để giữ order.

## Đi từng bước qua một tình huống

Nếu mọi event của order 42 dùng cùng routing key, chúng thường đi cùng partition theo partitioner đang dùng. Hai order khác partitions không có tổng thứ tự từ offset. Tăng số partition có thể đổi mapping key theo cách client chọn partition, nên phải xem ảnh hưởng ordering trong quá trình chuyển.

## Hiểu cơ chế từ kết quả quan sát

Partition count giới hạn một phần parallelism của consumer group nhưng nhiều hơn cũng tăng metadata, replication và vận hành. Một hot key vẫn nằm trên một partition; chia partition không tự chia một invariant theo key. Cần thay mô hình key hoặc xử lý hot entity riêng nếu product cho phép.

## Khái niệm và mô hình làm việc

Partition là ordering/replay/ownership unit; ordering toàn topic không được đảm bảo qua nhiều partitions.

## Cơ chế và những ranh giới cần giữ

Partition key theo business aggregate giữ order cần thiết; hot keys hạn chế throughput. Tăng partition count có thể đổi key mapping tùy partitioner.

## Áp dụng vào hệ thống thật

Order events theo order_id, migration CDC theo source primary key hoặc transaction protocol cần thiết.

## Những đường lỗi cần hiểu

Một tenant cực hot làm lag một partition; globally ordered design chỉ dùng một partition thành bottleneck.

## Lần theo bằng chứng khi có sự cố

Per-partition rates/lag/skew, sample key distribution và consumer utilization.

## Đánh đổi và giới hạn sử dụng

Nhiều partitions tăng parallelism/metadata/operational overhead; chọn từ expected throughput và key semantics.

## Thực hành, debugging và kết luận

Đo traffic/lag per partition thay vì chỉ average topic. Test key skew và ordering khi rollout partition strategy. Chọn key từ yêu cầu nghiệp vụ và mức phân tán workload, không chỉ hash random để biểu đồ cân bằng.


## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kafka.apache.org/41/design/design/)
