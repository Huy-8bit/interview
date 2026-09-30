# Traffic Generator — kết quả kiểm chứng

[Mục lục](README.md) · [Thiết kế và live guide](TRAFFIC_GENERATOR.md) · [API contracts](API_CONTRACTS.md)

Chạy ngày **2026-09-30** trên Docker Desktop/macOS ARM64, engine 8 GB/8 CPU. PostgreSQL 16.9 primary/replica, Kafka 3.9.1 ba brokers, Redis 7.4.4 sáu nodes, Debezium 3.2.4.Final. Các số latency dưới đây là snapshot của workload chức năng trong máy lab, không phải benchmark hay SLO.

## 1. Khởi động và phạm vi client

`docker compose up --build -d --wait` thành công, gồm container `traffic-generator` healthy, default continuous/5 virtual users/2000ms. Generator đợi bốn API healthy và Debezium initialization completed. Image chỉ cài HTTPX/Pydantic Settings cùng dependency của chúng; không có client PostgreSQL/Redis/Kafka, database credentials hay Docker socket. Mọi thay đổi dữ liệu của generator đi qua REST.

`TRAFFIC_ENABLED=false TRAFFIC_MODE=scenario` exit 0 với counts rỗng, không có request hoặc flow_started. [JSON logs](evidence/traffic/disabled.jsonl). Trong `make test`, generator được pause và restore; SIGTERM ghi final summary, flow đang chạy được cancel.

Migration 0002 thêm nullable simulation_run_id trên volume primary hiện hữu. Service test chứng minh DELETE từ chối row thường/run khác; row đúng run bị xóa và cache invalidated. Không reset database/volume hay xóa dữ liệu trước đó để triển khai generator.

## 2. Hai scenario kiểm chứng bằng dữ liệu thật

Orchestrator [traffic_scenarios.sh](../scripts/traffic_scenarios.sh) lấy Kafka end offsets trước mỗi scenario; observer toolbox chỉ đọc từ các offsets đó và lọc đúng flow/row. Mỗi scenario exit 0 và đúng một flow_completed. Force duplicate/error rate 1; FAIL scenario delete rate 1, PASS scenario delete rate 0. Continuous traffic khác vẫn có thể chạy song song; không dùng global topic count để suy luận.

| Chỉ số | FAIL + DELETE | PASS |
|---|---:|---:|
| HTTP attempts | 20 | 15 |
| HTTP 2xx | 18 | 14 |
| Expected non-2xx | 2 (replica 404, injected 422) | 1 (injected 422) |
| Average / p95 attempt latency | 13.49 / 34.20ms | 7.43 / 24.24ms |
| Vehicles / inspections quan sát | 1 / 1 | 1 / 1 |
| Repair do consumer tạo, được query thấy | 1 | Không query nhánh này |
| Duplicate inspection verified | 1 | 1 |
| DELETE thành công qua API | 1 | 0 |
| Cache expected/observed | MISS → HIT → MISS | MISS → HIT → MISS |
| Replica observations | 404 rồi ba lần 200 | Bốn lần 200 |

FAIL flow correlation ID: `7bc92ed3-e969-4799-8c8f-b0258e791a44`; vehicle ID `733c4711-04a7-4d3c-b681-fc558ac3bf98`; inspection ID `5ba3522c-0cba-40b8-9b52-2993b0e50b27`; repair ID `19af4d6e-cfb2-4f69-8180-e39fcadf3e8c`.

Observer kiểm:

- Tất cả requests cùng correlation ID; request ID khác nhau cho từng attempt và response echo đúng ID.
- Hai POST cùng key trả cùng inspection ID; list API có đúng một inspection cho xe.
- FAIL có domain events vehicle.created, vehicle.updated, warranty.created, inspection.failed, repair.created; PASS có inspection.passed. Tất cả giữ correlation ID của flow.
- CDC Vehicle đủ c/u/d/tombstone với matching run marker; Warranty c; Inspection c/u; Repair c cho FAIL. Mỗi CDC row record có source.connector=postgresql và source.lsn khác null.
- Cache headers đúng ba mốc; DELETE trả 204, query VIN trên primary trả [].

Bằng chứng: [FAIL result + raw domain/CDC records](evidence/traffic/fail-result.json), [FAIL request logs](evidence/traffic/fail.jsonl), [PASS result](evidence/traffic/pass-result.json), [PASS logs](evidence/traffic/pass.jsonl). CDC không có HTTP correlation field; observer nối bằng row ID/vehicle_id/run marker. Lần đọc mục tiêu 0ms trả 404 ở elapsed 2.42ms; các mốc 100/500/1000ms trả 200 ở 106.53/507.63/1012.41ms. Đây là eventual consistency hợp lệ, không làm scenario fail.

## 3. Continuous traffic và dependency outages

Bài thử [traffic_drills.sh](../scripts/traffic_drills.sh) chạy với worker continuous mặc định. Nó ghi run_id/heartbeat/counters trước và sau từng dependency outage, restore node rồi kiểm flow mới hoàn tất. Counter probe yêu cầu cùng run_id của toàn bài, heartbeat <15s; restart process không được coi là recovery thành công.

**Cả năm bài thử PASS**; bốn infrastructure outages được giữ ít nhất 10s trước khi đợi thêm tiến triển (đủ vượt Redis election timeout). Warranty được giữ down đến khi thấy flow lỗi và xe mới tiếp tục được tạo.

| Thành phần dừng | Counter khi đang down | Sau khôi phục |
|---|---|---|
| Kafka leader `kafka-2` | flows_completed 241 → 242 | Flow mới hoàn tất |
| Redis master `redis-4` | flows_completed 257 → 259 | Flow mới hoàn tất |
| PostgreSQL replica | replica_fallback_reads 69 → 72 | Flow mới hoàn tất |
| Debezium Connect | flows_completed 298 → 299 | Flow mới hoàn tất; bốn connectors/tasks RUNNING |
| Warranty Service | flows_failed 10 → 12; created_vehicles 316 → 318 | Flow mới hoàn tất |

Run ID giữ nguyên `8e5574c0-e3c6-4284-9819-d0d2b8c049b6`. Trong 88.56s của bài có thêm **1610 HTTP attempts, 101 xe, 96 flow hoàn tất, 7 flow lỗi, 30 repair được quan sát**, và một xe mô phỏng bị DELETE theo tỷ lệ mặc định. Counters tích lũy đã có dữ liệu trước baseline; các số tăng thêm được tính bằng final trừ baseline. Lỗi flow khi Warranty down là hành vi được kiểm chứng, không được bỏ khỏi báo cáo.

Cuối bài, PostgreSQL primary/replica streaming và bốn logical connectors/slots đã được kiểm lại; Kafka đủ ba broker/RF3/ISR3, Redis cluster_state=ok với 16.384 slots, ba master và ba replica. Generator vẫn enabled/continuous với năm users. Dữ liệu tiếp tục tăng sau thời điểm snapshot.

Bằng chứng: [baseline, từng outage/recovery và final counters](evidence/traffic/outages.json), [output orchestrator](evidence/traffic/outage-checks.txt), [sample logs retry/error/fallback](evidence/traffic/outage-log-sample.json), [Kafka/Redis topology cuối bài](evidence/traffic/clusters-final.json), [PostgreSQL/CDC final check](evidence/traffic/database-final.txt).

## 4. Automated checks

`make test`: **46 passed**, gồm Vehicle 6, Warranty 3, Inspection 2, Repair 2 và toolbox 33. Mười test cases mới kiểm retry 5xx, không retry 400/401/409/422, timeout rồi success giữ payload, ambiguous vehicle commit reconcile cùng VIN, flow failure isolation, bounded metrics, config ranges/alias. Vehicle thêm một test bảo vệ DELETE và VIN lookup. [Output đầy đủ](evidence/traffic/tests.txt).

`make lint`: shared/toolbox/generator và cả bốn services đều pass. [Output](evidence/traffic/lint.txt). Hai real scenarios bổ sung kiểm chứng vượt ngoài HTTP mocks; fault drills kiểm thực tế tiến triển khi dependency bị dừng. Sau chỉnh kiểm tra warranty 404 và shutdown, [10 traffic unit cases được chạy lại](evidence/traffic/traffic-unit-final.txt), đều pass. Tài liệu có 36 cặp Mermaid/SVG, gồm ba diagram mới cho generator; đã render, kiểm link và xem PNG để sửa nhãn chồng nhau.

## 5. Giới hạn bằng chứng

Không kiểm production TPS/SLO, network partition nhiều node, mất Docker host/storage, hay vô hạn thời gian chạy. Tests không khẳng định p95 của API ngoài workload này. Một healthy generator có thể chỉ đang retry; cần counter flow_completed và lag/oldest-outbox-age để đánh giá tiến triển.

Worker không resume flow lỗi khi restart, không rollback những bước đã commit và không replay DLQ tự động. DELETE mô phỏng giữ lịch sử downstream, marker chưa có authorization; không dùng như contract xóa production. Metrics/p95 và tỷ lệ FAIL/duplicate/delete là theo process/mẫu quan sát, không phải bảo đảm thống kê trên vài flow.
