# Performance debugging workflow

## Bài toán và ví dụ đầu tiên

P99 tăng không nói ngay CPU hay DB là nguyên nhân. Performance debugging là thu hẹp giả thuyết bằng các tín hiệu phân biệt, tránh đổi cùng lúc pool, timeout và replica count rồi không biết gì giúp.

## Đi từng bước qua một tình huống

Đầu tiên kiểm tra route/status, release time, offered/accepted/completed traffic và payload. Sau đó tách CPU saturation, memory/GC, queue/pool wait và dependency latency. Chọn CPU profile cho CPU, goroutine/trace cho waits, heap cho retention/churn.

## Hiểu cơ chế từ kết quả quan sát

Latency trung bình che tail; metrics tổng service có thể che một route hoặc tenant hot. Retry làm traffic tới dependency cao hơn request đầu vào. Container quota có thể tạo throttling dù host còn CPU. Mỗi giả thuyết cần kiểm tra trong cùng timestamp/workload.

## Khái niệm và mô hình làm việc

Bắt đầu từ regression trong user-visible latency/throughput, rồi phân loại CPU, wait, memory hoặc dependency.

## Cơ chế và những ranh giới cần giữ

Check traffic/build/config; correlate RED metrics, pool waits, runtime metrics và profiles. Separate mean/P99 và per-route distributions.

## Áp dụng vào hệ thống thật

20k RPS target: run stepped offered load, saturation knee và recovery after overload.

## Những đường lỗi cần hiểu

Closed-loop generator giảm load khi service chậm che queue growth; coordinated omission.

## Lần theo bằng chứng khi có sự cố

Use independent arrival scheduling khi phù hợp, report offered/accepted/completed rates và timeout accounting.

## Đánh đổi và giới hạn sử dụng

Load test có realistic data/cardinality/security work; hello-world không đại diện.

## Thực hành, debugging và kết luận

Mitigate bằng thay đổi đảo ngược được như giảm admission hoặc rollback release phù hợp evidence, rồi thu baseline sau. Verify cả errors, P99 và backlog recovery. Postmortem ghi causal chain và một regression/load scenario tái hiện, không chỉ danh sách dashboard đã mở.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](pprof.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)

## Thực hành có điều kiện kiểm chứng

Load gate phải bao accepted, rejected và timed-out operations. Generator closed-loop chỉ gửi request mới sau response sẽ giảm offered load khi service chậm; histogram có thể che queueing user thật gặp. Với open-loop schedule, report missed scheduling/overload ở generator để không nhầm client bottleneck thành server ceiling. Sau overload, verify queue drain và memory plateau.
