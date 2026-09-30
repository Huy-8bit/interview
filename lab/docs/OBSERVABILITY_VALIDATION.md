# Kết quả kiểm chứng distributed flow và observability

[Mục lục](README.md) · [Hướng dẫn chạy](GETTING_STARTED.md) · [Observability](OBSERVABILITY.md) · [System Design](SYSTEM_DESIGN.md)

Thực hiện ngày **2026-09-30** trên Docker Linux ARM64 trong OrbStack/macOS, VM 8 CPU và khoảng 8 GB RAM, có workload khác cùng máy. Các kết quả dưới đây đến từ stack thật; đây không phải benchmark độc lập hoặc SLO production.

## Startup và kiểm thử

Launcher hoàn tất **12/12 bước**, `READY` sau **99 giây** trong lượt dùng image cache và volumes hiện hữu. Log có RUNNING/WAIT/OK, thời gian từng bước và URL thực tế: [startup.txt](evidence/observability/startup.txt). Thời gian lần đầu pull/build sẽ khác. READY kiểm readiness và scrape; kiểm chứng workflow được chạy riêng bên dưới.

| Bộ test | Pass |
|---|---:|
| Vehicle | 7 |
| Warranty | 3 |
| Inspection | 5 |
| Repair | 2 |
| Shared unit và integration toàn stack | 42 |
| **Tổng** | **59** |

[Kết quả pytest](evidence/observability/tests.txt). Service tests dùng PostgreSQL schema riêng, Redis/Kafka thật khi thích hợp. Integration tests gọi APIs, đọc Kafka và kiểm DB/replication thật. Các nhánh timeout/worker termination có test kiểm soát bằng mock; không coi đó là fault drill hạ tầng. Ruff pass cho shared/toolbox và bốn service. Bộ tài liệu có **39 Mermaid/SVG pairs** được render và kiểm hash/link bằng `scripts/docs.py check`.

## Luồng nghiệp vụ và CDC thật

`make cdc-projection-check` đã PASS:

1. POST Vehicle với correlation ID mới → A commit vehicle/outbox/durable REST command → B tạo DEFAULT warranty qua REST.
2. C nhận domain event và WAL CDC, chuyển workflow sang READY; tạo inspection có đúng warranty ID.
3. Complete FAIL → Kafka → D hỏi coverage B qua internal REST → tạo repair có đúng vehicle/inspection/warranty IDs và covered=true.
4. Expire warranty qua REST → nhận CDC `op=u`, projection chuyển EXPIRED.
5. Probe xóa **chỉ warranty do chính nó vừa tạo**, với điều kiện cả warranty ID và vehicle ID → nhận `op=d` cùng before image và tombstone value=null; C giữ checkpoint delete và chuyển WAITING_WARRANTY.

[CDC envelope, source LSN, offsets và các ID](evidence/observability/cdc-projection.json) · [JSON logs của cùng correlation ID qua cả bốn service](evidence/observability/business-trace.jsonl).

Probe không thay đổi quy tắc REST-only của Traffic Generator. SQL delete thuộc công cụ kiểm chứng riêng vì API Warranty không có DELETE. Nhánh snapshot `op=r`, hai thứ tự đầu vào, duplicate, stale LSN và snapshot cũ sau delete được kiểm bằng service tests; không tuyên bố đã re-snapshot connector production trong probe này.

## Prometheus và Grafana

`make monitoring-check` đã xác nhận:

- **21 targets UP** ở trạng thái một instance cho mỗi API.
- PostgreSQL primary/replica kết nối được; Redis exporter đọc đủ 6 nodes; 4 connectors và 4 tasks RUNNING.
- Grafana datasource UID `lab-prometheus` được provision đúng URL; **10 dashboard** đã load qua Grafana API.
- Toàn bộ **134 PromQL queries hợp lệ và có series** trong lượt đo; không có panel rỗng.
- RPS, generator requests, CDC events, Kafka broker throughput và outbox publishes có giá trị thật >0; consumer lag/assignment tồn tại.
- CPU, RAM, memory limit và network samples có tên service cho đủ **17 thành phần bắt buộc**, gồm các API, generator, PostgreSQL, Kafka, Redis và Connect.
- HTTP metric dùng route template, không chứa UUID trong route labels.

[Targets, sample metrics và kết quả từng panel](evidence/observability/monitoring.json). CPU/RAM thuộc Linux containers/VM; memory limit có thể là VM capacity khi service không đặt hard limit. Histogram/rate cần nhiều scrape; một metric lỗi chưa phát sinh có thể bằng 0, không có nghĩa đã inject mọi loại lỗi.

## Consumer lag và scale

`make lag-demo` chạy consumer delay 500ms, REST-only load 4 virtual users/1.8s, giới hạn 300s hoặc 1000 xe. Sau 90s đo một consumer, scale Inspection lên 3 rồi đo khoảng 150s, vẫn giữ tải đang chạy.

| Phép đo | Kết quả |
|---|---:|
| Members | 1 → 3 |
| Source partitions | 6, không assign trùng ở steady state |
| Lag với một consumer | 0 → đỉnh 187 records |
| Lag sau rebalance | Đỉnh 243 → mẫu cuối 66 records |
| Trung bình ba mẫu lag cuối | 68.67 records |
| Throughput trung bình sau warm-up | 1.87 → 5.19 records/s |
| Throughput cửa sổ tốt nhất sau scale | 5.65 records/s |
| Xe mới được tạo trong pha 3 consumer | 268 |

Probe PASS yêu cầu lag tăng ít nhất 30, lag cuối dưới một nửa đỉnh sau rebalance, throughput tăng và workload vẫn tạo thêm ít nhất 50 xe. Phép so sánh tự động dùng trung bình pha một consumer và moving average 6 mẫu tốt nhất của pha ba consumer; giá trị 5.19 ở bảng là trung bình toàn phần sau warm-up để bổ sung góc nhìn. Không cam kết scale luôn đạt đúng 3×.

[Kết quả assertion](evidence/observability/lag-result.json) · [Mẫu một consumer](evidence/observability/lag-single.json) · [Mẫu ba consumer](evidence/observability/lag-scaled.json).

Repair cũng đã scale lên **3 members Stable**, mỗi member nhận đúng một partition của inspection-events; sau đó phục hồi về một instance. [Bằng chứng assignment và topology](evidence/observability/repair-rebalance.json).

## Phục hồi và phạm vi

Trong lượt thay toàn bộ broker images, đã phát hiện và xử lý: shared image tag gây recreate không cần thiết; JMX agent ảnh hưởng Kafka CLI; consumer kết thúc ở cleanup sau mất quorum; Connect giữ replication sessions cũ dù báo RUNNING. Cấu hình hiện dùng image riêng, agent chỉ ở broker, init process cho Connect và giám sát critical workers. Trường hợp Connect giữ slot cần clean restart worker theo [runbook](OBSERVABILITY.md#10-debug-và-giới-hạn); slots/offsets/volumes được giữ nguyên.

59 tests và probe CDC pass **sau khi phục hồi Connect**. Không dùng trạng thái UP/RUNNING thay bằng chứng data progress. Mười failure scenarios có hướng dẫn trong Observability; không tuyên bố cả mười đều được chạy lại ở lượt này. Các báo cáo cluster/PostgreSQL/traffic trước đây giữ phạm vi lịch sử riêng.

Kết thúc validation: traffic thường được bật lại, consumer delay về 0, Inspection/Repair mỗi service một instance. Không reset data volumes. Chưa kiểm chứng multi-host HA, production soak, automatic PostgreSQL failover, TLS/auth hoặc tracing phân tán.
