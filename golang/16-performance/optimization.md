# Optimization theo bottleneck

## Bài toán và ví dụ đầu tiên

Team muốn service nhanh hơn nhưng chưa có baseline. Optimization bắt đầu bằng mục tiêu đo được: P99, throughput completed, cost/request hoặc memory ceiling, rồi tìm phần giới hạn mục tiêu đó.

## Đi từng bước qua một tình huống

Nếu 80% latency là DB wait, giảm 10% CPU JSON có thể ít ảnh hưởng tổng latency. Nếu CPU saturation tạo queue delay, giảm CPU hot path có thể cải thiện nhiều hơn service time riêng. Đo đường đi request và capacity trước khi chọn cache, pool hay concurrency.

## Hiểu cơ chế từ kết quả quan sát

Mỗi tối ưu đổi trade-off: cache thêm freshness/invalidations, pooling thêm ownership, batching thêm wait, sharding thêm coordination. Amdahl-style reasoning nhắc rằng phần không cải thiện giới hạn tổng lợi ích. Không xóa validation hay timeout để benchmark đẹp hơn contract thực.

## Khái niệm và mô hình làm việc

Tối ưu phải cải thiện mục tiêu đo được trong constraints correctness/memory/latency.

## Cơ chế và những ranh giới cần giữ

Baseline, profile, hypothesis, one change, benchmark, production canary. Amdahl: tối ưu 10% cost có giới hạn lợi ích toàn hệ thống.

## Áp dụng vào hệ thống thật

Giảm N+1/pool churn trước viết custom allocator.

## Những đường lỗi cần hiểu

Microbench nhanh nhưng memory retention cao; sync.Pool gây data race do trả buffer sớm.

## Lần theo bằng chứng khi có sự cố

Compare same load/hardware and confidence; rollback khi error/P99 xấu dù ns/op tốt.

## Đánh đổi và giới hạn sử dụng

Complexity cần lợi ích đáng giữ; ưu tiên giảm work trước tune machinery.

## Thực hành, debugging và kết luận

Thay một giả thuyết, test output/invariants, benchmark rồi canary theo SLO. Giữ rollback và artifact profile. Dừng khi mục tiêu đã đạt và chi phí phức tạp của tối ưu tiếp không được chứng minh bởi workload.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](pprof.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)

## Thực hành có điều kiện kiểm chứng

Giả sử CPU profile 40% JSON,10% compression,50% khác: tối ưu compression 2× chỉ cải thiện tổng time lý tưởng khoảng 5%, không 2× toàn API. Nếu DB wait chiếm wall latency lớn, CPU savings có thể không đổi P99 nhưng giảm cost. Ghi mục tiêu rõ: latency, throughput/core hay memory; tránh dùng một benchmark metric thay cho tất cả.
