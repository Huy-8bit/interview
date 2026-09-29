# Queues và recovery capacity

## Bài toán và ví dụ đầu tiên

Một API có bước gửi email mất vài giây nhưng user chỉ cần biết order đã được nhận. Queue tách thời điểm chấp nhận khỏi hoàn tất, với điều kiện job được lưu bền trước response accepted nếu hệ thống cam kết không mất.

## Đi từng bước qua một tình huống

Producer ghi intent, worker xử lý có retry và ack/checkpoint. Crash sau effect trước ack tạo duplicate, nên consumer phải idempotent. Queue trong memory nhanh và đơn giản nhưng process chết có thể mất nội dung; durability là lựa chọn contract, không thuộc từ queue mặc định.

## Hiểu cơ chế từ kết quả quan sát

Arrival vượt completion dài hạn làm backlog tăng bất kể broker nào. Cần bound bytes/age và admission, DLQ owner cho lỗi permanent, ordering policy khi retry. Chọn job table, task broker hay log Kafka từ requirements scheduling/replay/fanout cụ thể.

## Khái niệm và mô hình làm việc

Queue tách arrival và service rate nhưng không chữa overload dài hạn; oldest age phản ánh user delay.

## Cơ chế và những ranh giới cần giữ

Bound retention/storage/in-flight; arrival λ, service μ: nếu μ≤λ backlog không drain. Recovery time≈backlog/(μ−λ) khi rates ổn định.

## Áp dụng vào hệ thống thật

Backlog1M, process8k/s, new5k/s →~333s drain ideal.

## Những đường lỗi cần hiểu

Scale consumers tăng DB contention làm μ giảm; queue full không có producer policy.

## Lần theo bằng chứng khi có sự cố

Queue age, growth derivative, retries, partition skew và sink saturation.

## Đánh đổi và giới hạn sử dụng

Durable queue giữ work qua crash nhưng cần replay/idempotency; memory channel phù hợp scope process.

## Thực hành, debugging và kết luận

Đo oldest age và completed rate cùng depth. Test consumer down lâu và recovery ramp. Queue mua thời gian và decouple, không tạo capacity xử lý vô hạn hay tự đảm bảo exactly-once external effects.


## Đọc tiếp

- [System design framework cho Senior Go](system-design-framework.md)
- [Design High-Throughput API — 20,000 RPS](design-high-throughput-api.md)
- [Design Migration Platform — 4–5 Billion Records](design-migration-platform.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
