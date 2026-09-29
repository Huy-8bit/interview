# Structured logging có context

## Bài toán và ví dụ đầu tiên

Một incident có hàng triệu dòng “request failed” nhưng không biết operation nào đã commit. Log hữu ích phải mô tả sự kiện/state transition cùng định danh và cause đủ để dựng timeline.

## Đi từng bước qua một tình huống

Structured log giữ các field như route, operation_id, attempt, error_class và duration. Log ở boundary sở hữu quyết định, tránh mỗi layer lặp cùng lỗi. Request ID nhận diện một attempt, operation ID liên kết retry; hai mục đích khác nhau.

## Hiểu cơ chế từ kết quả quan sát

Log không là durable ledger cho nghiệp vụ vì có sampling/drop/retention. Không ghi token, credential hay full payload chỉ để debug dễ. High-volume success logs có thể tốn CPU/I/O; chọn mức và sampling theo giá trị điều tra, giữ errors quan trọng có policy.

## Khái niệm và mô hình làm việc

Log là event evidence có time, severity, operation và correlation; không thay metrics cho rates.

## Cơ chế và những ranh giới cần giữ

Dùng log/slog với fields bounded, errors một lần ở boundary; redact secrets/PII, sampling noisy events và backpressure cho exporter.

## Áp dụng vào hệ thống thật

Log operation_id, route template, outcome và dependency name để pivot trace.

## Những đường lỗi cần hiểu

Log mỗi retry/layer gây noise; sync logging I/O làm latency; token xuất raw.

## Lần theo bằng chứng khi có sự cố

Check dropped log counts, ingestion lag và repeated errors cùng logical request.

## Đánh đổi và giới hạn sử dụng

Debug detail có cost/security; enable targeted sampling có thời hạn.

## Thực hành, debugging và kết luận

Test redaction và field consistency trên success/error/cancel. Khi incident, query theo operation và release marker rồi đối chiếu DB/provider state. Đo logging overhead nếu CPU/alloc tăng sau thêm format ở hot loop.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md)
- [service-outage](../20-production-scenarios/service-outage.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://opentelemetry.io/docs/concepts/observability-primer/)

## Thực hành có điều kiện kiểm chứng

Một request retry3 lần có operation_id cố định và attempt index khác nhau. Log error cuối tại owning boundary; intermediate retries ở sampled debug/info theo policy để tránh noise. Slog fields dùng route template và dependency name, không dump headers/context. Khi log sink chậm, bounded async queue/drop policy phải bảo vệ request path và expose dropped count.
