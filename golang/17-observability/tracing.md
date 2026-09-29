# Tracing và critical path

## Bài toán và ví dụ đầu tiên

Một request qua bốn services mất 2 giây. Trace nối spans thành đường đi để biết thời gian ở từng dependency và khoảng trống giữa chúng, thay vì ghép logs thủ công bằng đồng hồ lệch.

## Đi từng bước qua một tình huống

Root span của request tạo context truyền xuống calls; server remote tiếp tục trace theo propagator/protocol. Span nên đặt quanh operation có ý nghĩa, gồm acquire wait khi cần giải thích latency. Retry attempts có thể là spans riêng gắn cùng operation identity.

## Hiểu cơ chế từ kết quả quan sát

Sampling nghĩa không phải request nào cũng có trace đầy đủ; thiếu span không chứng minh không có side effect. Clock skew và async boundaries cần đọc thận trọng. Không đưa secret hoặc unbounded payload vào attributes; cardinality/storage vẫn có chi phí.

## Khái niệm và mô hình làm việc

Trace nối spans của logical operation; elapsed request time chịu critical path và overlap.

## Cơ chế và những ranh giới cần giữ

Propagate context qua HTTP/gRPC; async messaging dùng link/parent model theo instrumentation. Span attributes phải useful/bounded, redact payloads.

## Áp dụng vào hệ thống thật

Checkout trace phân biệt pool wait, DB execution và provider latency.

## Những đường lỗi cần hiểu

Spans missing do context.Background; sampling bỏ failure; clocks lệch.

## Lần theo bằng chứng khi có sự cố

Pivot từ slow/error cohort; đối chiếu parent-child durations và queue stages chưa instrument.

## Đánh đổi và giới hạn sử dụng

Trace samples không thay rate metrics; sampling policy cân cost với incident visibility.

## Thực hành, debugging và kết luận

Test propagation qua middleware, goroutine và message metadata. Khi timeout, đối chiếu spans với durable state để biết outcome. Trace phục vụ causal investigation, metrics phục vụ trend/alert; dùng cả hai theo câu hỏi thay vì instrument mọi hàm nhỏ.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md)
- [service-outage](../20-production-scenarios/service-outage.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://opentelemetry.io/docs/concepts/observability-primer/)

## Thực hành có điều kiện kiểm chứng

Request fan-out 3 calls chạy song song mỗi call 100 ms có tổng span duration300 ms nhưng critical path khoảng 100 ms cộng overhead. Nếu API duration500 ms, tìm queue/admission/uninstrumented gaps hoặc sequential stages. Tail sampling có thể giữ error traces nhưng collector vẫn cần bounded state. Không dùng trace sampling ratio để suy exact error rate; metrics trả lời rate.
