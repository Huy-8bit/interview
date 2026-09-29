# Cache, freshness và tải khi cache lỗi

Cache tạo thêm bản sao dữ liệu và một dependency. Từ cache-aside đơn giản, lần theo race giữa fill/update, hot-key expiry và Redis outage để hiểu tại sao hit ratio cao chưa đủ. Mọi cache cần giới hạn memory, freshness policy và budget cho nguồn dữ liệu khi miss.

## Bắt đầu và cách thực hành

Bắt đầu với [redis-basics](redis-basics.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Cache-aside: miss path cũng là production path](cache-aside.md) | P1 |
| [Cache stampede và refresh coalescing](cache-stampede.md) | P1 |
| [Caching patterns và consistency](caching-patterns.md) | P1 |
| [Redis lock và fencing](distributed-lock.md) | P1 |
| [Redis failure game day](failure-scenarios.md) | P1 |
| [Redis atomic rate limiting](rate-limiting.md) | P1 |
| [Redis: data structures và bounded memory](redis-basics.md) | P1 |
| [Redis Cluster: slots và hot keys](redis-cluster.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
