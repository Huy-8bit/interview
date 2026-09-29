# SLI, SLO, SLA và error budget

## Bài toán và ví dụ đầu tiên

Team nói service phải “nhanh và ổn định” nhưng không thống nhất đo success nào. SLI là chỉ số quan sát chất lượng, SLO là mục tiêu cho chỉ số trong cửa sổ, SLA là cam kết với bên sử dụng có điều khoản riêng.

## Đi từng bước qua một tình huống

Ví dụ SLI là tỷ lệ request hợp lệ trả kết quả đúng dưới 300 ms; SLO đặt tỷ lệ mục tiêu theo tháng. Cần định nghĩa denominator, routes, lỗi client và request bị reject có được tính không. Availability200 với dữ liệu stale quá mức có thể vẫn thất bại theo product.

## Hiểu cơ chế từ kết quả quan sát

Error budget là phần sai lệch được chấp nhận trong SLO, giúp thảo luận release risk và reliability work. Burn rate mô tả tốc độ tiêu budget so với mức cho phép; cửa sổ ngắn/dài hỗ trợ phân biệt spike với sự cố kéo dài. Không suy SLA pháp lý từ một dashboard SLO nội bộ.

## Khái niệm và mô hình làm việc

SLI đo outcome; SLO là target nội bộ theo window; SLA là cam kết hợp đồng với consequences.

## Cơ chế và những ranh giới cần giữ

Define eligible events, good events và window. Availability với timeout/5xx accounting; latency SLO phải nêu percentile hoặc fraction dưới threshold.

## Áp dụng vào hệ thống thật

99.9% monthly availability cho endpoint critical có error budget khoảng 0.1% eligible events.

## Những đường lỗi cần hiểu

Loại timeout khỏi denominator; average latency dưới target nhưng P99 tệ; alert mọi CPU spike thay user impact.

## Lần theo bằng chứng khi có sự cố

Burn-rate alerts nhiều windows và dependency diagnostics; validate measurement tại edge.

## Đánh đổi và giới hạn sử dụng

Không hứa 100% khi cost/architecture không cho; SLO dẫn trade-offs release/reliability.

## Thực hành, debugging và kết luận

Dùng dữ liệu user-visible, kiểm tra instrumentation không bỏ timeout/client disconnect quan trọng. Khi incident, ưu tiên mục tiêu sản phẩm thay vì tối ưu mọi metric. Review SLO với workload và nhu cầu thực, tránh chọn nhiều số chín chỉ vì nghe tốt.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md)
- [service-outage](../20-production-scenarios/service-outage.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://opentelemetry.io/docs/concepts/observability-primer/)
