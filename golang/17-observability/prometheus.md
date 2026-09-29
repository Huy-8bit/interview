# Prometheus metrics cho Go

## Bài toán và ví dụ đầu tiên

Một counter http_requests_total tăng từ 1000 lên 1600 trong một phút. Giá trị hiện tại không phải 1600 request/s; cần rate theo cửa sổ. Prometheus lưu time series có labels, phù hợp quan sát xu hướng và alert có ngữ cảnh.

## Đi từng bước qua một tình huống

Counter dùng cho totals, gauge cho in-flight/queue depth, histogram cho latency distribution. Buckets phải khớp mục tiêu latency và workload; bucket quá thưa quanh SLO làm phép ước lượng percentile kém hữu ích. Route label dùng template để giới hạn series.

## Hiểu cơ chế từ kết quả quan sát

Scrape có thể trễ/mất, process restart làm counters reset và alert cần dùng query semantics phù hợp. Metrics endpoint không nên thực hiện query DB đắt trong mỗi scrape. Cardinality của mỗi tổ hợp labels nhân lên toàn fleet nên một field userID có thể gây vấn đề lớn.

## Khái niệm và mô hình làm việc

Prometheus scrape samples theo time series identity; labels quyết định memory/query cost.

## Cơ chế và những ranh giới cần giữ

Expose private metrics endpoint, choose histogram buckets theo SLO, track runtime/process và application counters. Rate counters qua window đủ samples.

## Áp dụng vào hệ thống thật

Pool InUse gauge, acquire wait histogram, requests by route/status class.

## Những đường lỗi cần hiểu

Label raw URL/order ID tạo hàng triệu series; buckets không bao quanh 200ms SLO.

## Lần theo bằng chứng khi có sự cố

Check scrape errors/duration, cardinality growth và aggregation across replicas.

## Đánh đổi và giới hạn sử dụng

Metrics endpoint phải rẻ; không chạy expensive DB query mỗi scrape.

## Thực hành, debugging và kết luận

Test metrics output và alert với synthetic failures/traffic thấp. Alert theo user impact và burn rate phù hợp SLO thay vì một spike đơn lẻ không actionable. Nối alert tới dashboard/runbook có owner và bước kiểm chứng cụ thể.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md)
- [service-outage](../20-production-scenarios/service-outage.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://prometheus.io/docs/practices/histograms/)

## Thực hành có điều kiện kiểm chứng

Với classic histogram bucket le="0.2", good fraction có thể lấy rate(bucket≤0.2)/rate(count) cùng route/window; validate bucket tồn tại và timeout policy. Counter series theo status class/service/route có bound, còn user_id khiến cardinality tăng theo customer count. Scrape endpoint không nên tự chạy DB health query vì nhiều Prometheus replicas có thể nhân load.
