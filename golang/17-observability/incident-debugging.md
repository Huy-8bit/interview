# Incident debugging với evidence

## Bài toán và ví dụ đầu tiên

P99 tăng và alert đánh thức on-call. Mục tiêu đầu là giảm tác động và bảo toàn thông tin đủ tìm cause, không phải chứng minh một phỏng đoán bằng cách mở thật nhiều dashboard.

## Đi từng bước qua một tình huống

Xác định route/users affected, thời điểm bắt đầu, release/config changes và offered/completed traffic. Đặt giả thuyết như pool wait tăng rồi tìm metric có thể bác bỏ: DB.Stats, query duration, goroutine stacks. Chọn mitigation nhỏ có rollback và ghi timestamp.

## Hiểu cơ chế từ kết quả quan sát

Correlation với deploy hữu ích nhưng chưa là causation; traffic/payload/dependency cũng có thể đổi. Restart làm giảm memory tạm thời nhưng xóa state/profile có giá trị. Thu evidence có phạm vi nếu không làm chậm mitigation quan trọng.

## Khái niệm và mô hình làm việc

Incident response ưu tiên giảm impact rồi tìm cause bằng timeline có thể kiểm chứng.

## Cơ chế và những ranh giới cần giữ

Assess scope/SLO, recent changes, dependencies; choose reversible mitigation; snapshot profiles/logs trước restart khi không trì hoãn recovery.

## Áp dụng vào hệ thống thật

Rollback regression đã correlate, shed optional traffic, pause backfill đang chiếm DB.

## Những đường lỗi cần hiểu

Thay nhiều configs cùng lúc mất causal signal; restart toàn fleet che evidence và tạo cold-cache storm.

## Lần theo bằng chứng khi có sự cố

Track hypothesis, evidence for/against, action/time/outcome; aftercare verify recovery và backlog.

## Đánh đổi và giới hạn sử dụng

Mitigation không là root-cause fix; postmortem cần owner và measurable prevention.

## Thực hành, debugging và kết luận

Sau recovery, kiểm tra backlog/unknown operations và dữ liệu, không chỉ alert xanh. Viết timeline, contributing factors và action có owner/verification. Regression scenario nên tái hiện trigger và failure path, tránh chỉ thêm một checklist chung không kiểm chứng được.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md)
- [service-outage](../20-production-scenarios/service-outage.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://opentelemetry.io/docs/concepts/observability-primer/)

## Thực hành có điều kiện kiểm chứng

Tạo incident note gồm timestamp, hypothesis, evidence, action, owner và expected outcome. Ví dụ “pool wait tăng sau backfill” cần DB hold-time/active-session evidence; pause backfill là reversible experiment. Nếu latency không giảm, bác bỏ hoặc chỉnh hypothesis thay tiếp tục tăng pool theo cảm tính. Recovery note phải ghi remaining data reconciliation/backlog, không chỉ process health.
