# Điều tra sự cố bằng timeline và giả thuyết

Mỗi bài là tình huống mô phỏng có symptom, bằng chứng cần thu, mitigation và kiểm tra recovery. Con số được dùng để làm rõ reasoning, không là incident thật của repository. Đọc diễn tiến trước khi nhìn sơ đồ rút gọn và thử nêu một quan sát có thể bác bỏ chẩn đoán.

## Bắt đầu và cách thực hành

Bắt đầu với [high-cpu](high-cpu.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [API high latency](api-high-latency.md) | P1 |
| [DB pool exhausted](connection-pool-exhausted.md) | P1 |
| [Database query slowdown](database-slow.md) | P1 |
| [Duplicate business effect](duplicate-message.md) | P1 |
| [20,000 goroutines trong production](goroutine-leak.md) | P1 |
| [CPU95%, memory normal, RPS normal](high-cpu.md) | P1 |
| [Kafka consumer lag tăng](kafka-lag.md) | P1 |
| [Memory tăng liên tục](memory-growth.md) | P1 |
| [Production race/data corruption](race-condition.md) | P1 |
| [Redis unavailable và cache collapse](redis-down.md) | P1 |
| [Service outage: first15 minutes](service-outage.md) | P1 |
| [Traffic spike và load shedding](traffic-spike.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
