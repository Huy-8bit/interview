# Observability across services

## Bài toán và ví dụ đầu tiên

Request đi qua gateway, order, inventory và payment. Một log “timeout” ở order chưa chỉ ra payment chưa nhận request hay đã commit rồi response mất. Observability nối tín hiệu giữa service và durable operation.

## Đi từng bước qua một tình huống

Trace context liên kết spans, request ID nhận diện một attempt và operation ID nhận diện ý định nghiệp vụ qua retries. Metrics đo rates/latency/errors theo route/dependency hữu hạn. Logs chứa transition/cause cần thiết và tránh token/payload nhạy cảm.

## Hiểu cơ chế từ kết quả quan sát

Distributed traces có sampling và có thể mất, nên không là nguồn sự thật cho payment outcome. Durable records/provider reference mới hỗ trợ reconciliation. High-cardinality labels như user ID làm hệ metrics phình; giữ ID trong logs/traces có policy phù hợp.

## Khái niệm và mô hình làm việc

Correlation cần request/trace/event IDs và semantic metrics xuyên boundaries.

## Cơ chế và những ranh giới cần giữ

HTTP/gRPC propagate trace context; Kafka dùng headers và links. Consistent service/version/operation attributes, không raw user IDs làm metric labels.

## Áp dụng vào hệ thống thật

Một checkout trace nối inventory call, DB Tx và outbox event processing latency.

## Những đường lỗi cần hiểu

Sampling bỏ rare failures; clock skew gây timeline khó đọc; logs thiếu operation ID.

## Lần theo bằng chứng khi có sự cố

Start từ SLO symptom, pivot metric→trace→log; compare deployment cohorts.

## Đánh đổi và giới hạn sử dụng

100% tracing có overhead/storage; sampling và error-focused capture cần privacy policy.

## Thực hành, debugging và kết luận

Dựng dashboard theo user-visible SLO rồi dependency timeline. Khi incident, so offered/accepted/completed và backlog, không chỉ CPU từng pod. Test telemetry khi timeout/retry để một operation không bị hiểu thành nhiều success độc lập.


## Đọc tiếp

- [Microservices: independent ownership có chi phí](../11-software-architecture/microservices.md)
- [Distributed failure matrix](../12-distributed-systems/failure-scenarios.md)
- [tracing](../17-observability/tracing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://grpc.io/docs/guides/)

## Thực hành có điều kiện kiểm chứng

Một async notification có producer request kết thúc trước consumer bắt đầu. Giữ event ID và trace metadata trong envelope, consumer tạo processing span/link theo instrumentation convention. Không giữ nguyên expired request deadline làm job fail ngay. Đo event_age tại consumer và total delivery latency vì HTTP producer span ngắn không chứng minh user nhận notification nhanh.
