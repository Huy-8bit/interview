# Observability như phần design

## Bài toán và ví dụ đầu tiên

Design có cache, broker và nhiều workers nhưng không biết lúc nào job user yêu cầu thực sự xong. Observability của architecture phải theo user operation qua các component, không chỉ health từng box.

## Đi từng bước qua một tình huống

Định nghĩa accepted/completed/failed/pending và durable operation ID. Metrics SLO phản ánh latency/outcome người dùng thấy; traces nối synchronous hops; logs/state records nối async attempts. Queue age/freshness giúp đo phần sau response202.

## Hiểu cơ chế từ kết quả quan sát

Telemetry có sampling/loss và không thay ledger/durable state. Cardinality phải bound, secrets được redacted. Alert cần owner và action: broker lag tăng là tín hiệu, nhưng mức ảnh hưởng user còn phụ thuộc oldest job age, retention và deadline.

## Khái niệm và mô hình làm việc

Thiết kế phải cho biết dùng metric/trace/state nào chứng minh invariant và SLO.

## Cơ chế và những ranh giới cần giữ

SLIs tại boundary user thấy; queue age cho async completion; durable IDs cho reconciliation; cardinality bounded và protected diagnostics.

## Áp dụng vào hệ thống thật

Payment unknown age quan trọng hơn chỉ HTTP5xx; migration version gaps quan trọng hơn worker CPU.

## Những đường lỗi cần hiểu

Dashboards chỉ infra xanh nhưng work stalled; retries counted success nhiều lần.

## Lần theo bằng chứng khi có sự cố

Track logical operations separately from attempts và source/target state mismatches.

## Đánh đổi và giới hạn sử dụng

Telemetry có overhead/storage/privacy; sampling phải giữ incident visibility.

## Thực hành, debugging và kết luận

Trong design review, chọn một failure rồi chỉ ra metric phát hiện, evidence phân biệt cause và dấu hiệu recovery. Test instrumentation cùng fault injection để không có hệ thống “có dashboard” nhưng không giải thích được unknown outcome.


## Đọc tiếp

- [System design framework cho Senior Go](system-design-framework.md)
- [Design High-Throughput API — 20,000 RPS](design-high-throughput-api.md)
- [Design Migration Platform — 4–5 Billion Records](design-migration-platform.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
