# Message retries và poison data

## Bài toán và ví dụ đầu tiên

Consumer gặp DB unavailable trong vài giây; thử lại có thể giúp. Nhưng record JSON sai schema sẽ lỗi mãi. Retry message phải phân loại transient/permanent và giới hạn tuổi/attempt, nếu không một poison message chiếm worker vô thời hạn.

## Đi từng bước qua một tình huống

Transient failure vào retry có delay/jitter; permanent failure được giữ cùng context để điều tra theo policy. Nếu cần ordering per key, chuyển record lỗi sang retry topic rồi xử lý record sau có thể đảo nghĩa; có thể phải pause key/partition hoặc dùng versioned updates.

## Hiểu cơ chế từ kết quả quan sát

Retry cần giữ event ID gốc để dedup, lưu số attempt và nguyên nhân không chứa secret. Broker/client ack trước khi lưu durable retry có thể làm mất record; ack sau publish retry có thể duplicate khi crash. Thiết kế cửa sổ đó theo at-least-once và consumer replay-safe.

## Khái niệm và mô hình làm việc

Retry cần phân loại transient/permanent, delay, max age và replay-safe effect.

## Cơ chế và những ranh giới cần giữ

Retry-in-place giữ order nhưng block partition; retry topic cho progress nhưng có thể reorder key. Dùng attempts/original ID và exponential jitter; DLQ sau policy.

## Áp dụng vào hệ thống thật

DB transient retry trong short budget rồi park record; validation error vào quarantine với reason.

## Những đường lỗi cần hiểu

Immediate requeue chiếm CPU/broker; retry tạo new ID làm dedup thất bại.

## Lần theo bằng chứng khi có sự cố

Retry attempts, age, categories, original correlation ID và fresh-work throughput.

## Đánh đổi và giới hạn sử dụng

Không retry vô hạn; quyết định ordering khi tách retry lane.

## Thực hành, debugging và kết luận

Đo oldest retry age, attempt distribution và số final failures. Test dependency down lâu hơn buffer và replay sau fix schema. Không tạo vòng retry vô hạn giữa main queue và retry queue; có owner cho DLQ và điều kiện đưa lại.


## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kafka.apache.org/41/design/design/)

## Thực hành có điều kiện kiểm chứng

Xét recordA1 lỗi, A2 cùng key tới sau. Retry-in-place giữ A2 chờ, tăng latency nhưng giữ order. Retry topic cho A2 chạy sớm nên target cần version guard hoặc park key tới khi A1 resolved. Nêu rõ policy cho poison message: bỏ qua có thể phá aggregate state, vì vậy DLQ phải đi cùng blocked-key/reconciliation decision.
