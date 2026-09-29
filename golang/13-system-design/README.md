# Xây hệ thống qua từng phiên bản có lý do

Các bài bắt đầu từ một API/database hoặc control/worker flow đơn giản, chỉ thêm replica/cache/queue khi requirement hoặc bottleneck đã rõ. Mỗi sơ đồ có phần đọc nodes, arrows và failure boundaries. Capacity là ước lượng với assumptions; các mục tiêu RPS hoặc số rows chưa phải kết quả benchmark production.

## Bắt đầu và cách thực hành

Bắt đầu với [system-design-framework](system-design-framework.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Caching trong system design](caching.md) | P1 |
| [Capacity estimation có units](capacity-estimation.md) | P1 |
| [Database scaling theo bottleneck](database-scaling.md) | P1 |
| [Design API Gateway](design-api-gateway.md) | P1 |
| [Design Chat System](design-chat-system.md) | P1 |
| [Design File Processing](design-file-processing.md) | P1 |
| [Design High-Throughput API — 20,000 RPS](design-high-throughput-api.md) | P1 |
| [Design Job Processing System](design-job-processing-system.md) | P1 |
| [Design Migration Platform — 4–5 Billion Records](design-migration-platform.md) | P1 |
| [Design Notification System](design-notification-system.md) | P1 |
| [Design Payment System](design-payment-system.md) | P1 |
| [Design URL Shortener](design-url-shortener.md) | P1 |
| [Load balancing: connection versus request](load-balancing.md) | P1 |
| [Observability như phần design](observability.md) | P1 |
| [Queues và recovery capacity](queue.md) | P1 |
| [Sharding và partition ownership](sharding.md) | P1 |
| [System design framework cho Senior Go](system-design-framework.md) | P0 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
