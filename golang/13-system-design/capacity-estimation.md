# Capacity estimation có units

## Bài toán và ví dụ đầu tiên

Team muốn biết bao nhiêu replicas cần cho traffic dự kiến. Capacity estimation là một mô hình có đơn vị và assumptions để định hướng đo, không phải lời hứa chỉ cần chia RPS cho một con số benchmark.

## Đi từng bước qua một tình huống

Tách peak/average, reads/writes, payload distribution và service time. Trong steady state, mean in-flight xấp xỉ rate × mean time trong cùng boundary. Ví dụ 1000 req/s × 0,1 s = 100 requests tồn tại trung bình, không phải 100 connections cho mọi protocol.

## Hiểu cơ chế từ kết quả quan sát

Storage cần payload, indexes, replicas và retention; egress cần fanout và protocol overhead. Skew làm một key/partition quá tải dù tổng capacity còn dư. Headroom cho zone loss, deploy surge và background jobs phải cộng theo scenario, không dùng một hệ số bí ẩn thay mọi reasoning.

## Khái niệm và mô hình làm việc

Ước lượng là model có assumptions để tìm bottleneck, không là performance guarantee.

## Cơ chế và những ranh giới cần giữ

RPS×mean latency(s)=mean in-flight trong steady state; events/s×bytes/event×retention(s) cho raw storage. Cộng indexes/replicas/protocol overhead và headroom riêng, không trộn units MB/MiB.

## Áp dụng vào hệ thống thật

20k RPS×50ms=1000 concurrent; cache90% reads và95% hit cho900 misses/s.

## Những đường lỗi cần hiểu

Lấy peak làm daily average; dùng P99 thay mean trong Little's Law; quên replicas và rollout surge.

## Lần theo bằng chứng khi có sự cố

So estimates với load generator offered rate, actual bytes và DB hold time; revise assumptions theo samples.

## Đánh đổi và giới hạn sử dụng

Rough estimate hữu ích hơn precision giả; sensitivity analysis hit ratio/latency cần thiết.

## Thực hành, debugging và kết luận

Đối chiếu estimates với load test và production metrics rồi sửa model. Ghi rõ decimal/binary units và mean/P99. Khi một assumption đổi như cache hit từ95% xuống0%, tính lại miss load để biết dependency nào cần protection.


## Đọc tiếp

- [System design framework cho Senior Go](system-design-framework.md)
- [Design High-Throughput API — 20,000 RPS](design-high-throughput-api.md)
- [Design Migration Platform — 4–5 Billion Records](design-migration-platform.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
