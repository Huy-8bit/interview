# 21 — Production troubleshooting playbook

Mỗi vấn đề: **Symptoms → Possible causes → Metrics → How to debug → Remediation → Trade-offs**. Những mục có nhãn **[gặp trong lab]** là sự cố thật xảy ra khi xây dựng lab này.

---

## 1. Consumer lag tăng
- **Symptoms**: `kafka_consumergroup_lag` tăng liên tục; e2e latency tăng; dữ liệu downstream trễ.
- **Causes**: traffic tăng/burst; xử lý chậm hơn (DB/API downstream chậm); consumer ít hơn partition cần; rebalance liên tục; hot partition; poison message chặn partition (inline retry); consumer chết (group Empty).
- **Metrics**: lag theo partition (đều hay chỉ vài partition?), `rate(consumed_total)` vs `rate(messagesin)`, `processing_duration_seconds`, `rebalance_events_total`, members per group.
- **Debug**: `kcli group -group G -watch 2s` (lag mỗi partition + owner); lag chỉ ở 1 partition → hot key/poison; lag đều → capacity; group `Empty` → consumer không chạy (lab 05 gặp: notification-group `Empty`, lag 2898 do container bị stop).
- **Remediation**: scale consumer (≤ partition), tối ưu xử lý (batch DB write, song song theo key), tăng partition (cẩn thận ordering), tách hot key, giảm `max.poll.records` nếu bị kick.
- **Trade-off**: thêm partition đổi mapping key; xử lý song song trong partition phức tạp hoá ordering/commit.

## 2. Broker CPU cao
- **Causes**: nén lại do `compression.type` topic ≠ producer; TLS; quá nhiều request nhỏ (linger=0, batch nhỏ — performance C: 6672 request vs 174); nhiều partition; consumer đọc dữ liệu cũ không nằm trong page cache (I/O); message format conversion (client cũ).
- **Metrics**: `rate(process_cpu_seconds_total)`, `requests_total` theo loại, `requesthandler_avg_idle_ratio`, `networkprocessoravgidlepercent`, `producemessageconversions_total`.
- **Remediation**: tăng batching phía client, dùng `compression.type=producer`, scale broker, quotas cho client ồn ào.

## 3. Disk gần đầy
- **Causes**: retention quá dài so với traffic; topic compacted không compact được (cleaner chết, key=null); partition lệch (hot partition dồn vào 1 broker); replica reassignment.
- **Metrics**: `kafka_log_log_size` theo topic/broker, disk usage node exporter, `uncleanable_partitions_count`.
- **Remediation**: giảm `retention.ms/bytes` (hiệu lực ở lần check tiếp theo), `kafka-delete-records`, thêm disk/broker + reassign, tiered storage (KIP-405).
- **Trade-off**: giảm retention = mất khả năng replay; consumer đang chậm có thể `OFFSET_OUT_OF_RANGE`.

## 4. Under-replicated partitions
- **Causes**: broker down; follower chậm (disk, GC, network); replication bị chặn [gặp trong lab: failures/replica_out_of_sync chặn port 29092 → 17 lần ISR shrink]; reassignment đang chạy.
- **Metrics**: `underreplicatedpartitions` theo broker (broker nào là leader của URP → follower nào thiếu), `replicafetchermanager_maxlag`, `isrshrinks_total`.
- **Debug**: `kafka-topics --describe --under-replicated-partitions` → replica nào thiếu chung → broker đó có vấn đề.
- **Remediation**: khôi phục broker; tăng `num.replica.fetchers`; sửa network.

## 5. Offline partition
- **Causes**: mọi replica trong ISR (và ELR) chết; mất KRaft quorum không bầu được leader.
- **Metrics**: `offlinepartitionscount` > 0 (critical), `activecontrollercount`.
- **Remediation**: khôi phục broker có dữ liệu. Phương án cuối: unclean leader election (chấp nhận mất dữ liệu).
- **Trade-off**: availability vs consistency (xem [13](13-leader-election.md)).

## 6. ISR shrinking / flapping
- **Causes**: GC pause dài, disk chậm, network jitter, `replica.lag.time.max.ms` quá thấp, broker quá tải.
- **Metrics**: `isrshrinks/isrexpands` rate, GC time, request queue, disk latency.
- **Lưu ý**: ISR chỉ shrink với partition **có dữ liệu mới** — follower im lặng trên partition không có ghi vẫn "in sync" (lab 10).

## 7. Rebalance thường xuyên
- **Causes**: xử lý một batch > `max.poll.interval.ms`; session timeout quá thấp so với GC; deploy rolling; autoscaling; consumer crash loop.
- **Metrics**: `rebalance_events_total`, coordinator log `Preparing to rebalance group ... (reason: ...)`.
- **Remediation**: giảm `max.poll.records`, tăng `max.poll.interval.ms`, cooperative-sticky / KIP-848, static membership.
- **[gặp trong lab] Rebalance kéo dài 51s**: notification-consumer khởi động lại nhưng chỉ nhận partition sau 51s. Coordinator log: `Member notification-consumer-1-d636... in group notification-group has failed, removing it`. Nguyên nhân: LeaveGroup của instance cũ gửi đúng lúc **coordinator đang chuyển** (`__consumer_offsets` P41 đổi leader kafka-1 → kafka-3 do preferred leader election) → bị mất → member ma tồn tại tới hết `session.timeout.ms` mặc định 45s. Bài học: session timeout ngắn hơn cho consumer cần failover nhanh; đừng restart broker và consumer cùng lúc.

## 8. Producer timeout
- **Symptoms**: "records have timed out", `produce_error_total{error=...}`.
- **Causes**: ISR < min ISR (NOT_ENOUGH_REPLICAS bị retry tới hết delivery timeout); mất quorum (acks=all chờ follower chết); leader không reachable; buffer đầy; broker quá tải.
- **[gặp trong lab]**: client chỉ thấy "timed out" trong khi broker đếm `kafka_network_requestmetrics_errors_total{error="NOT_ENOUGH_REPLICAS"}` 276 lần trong 8s → **luôn đối chiếu error metric phía broker**; bật log client mức info khi điều tra.
- **Remediation**: khôi phục ISR; với dữ liệu ít quan trọng có thể giảm acks (có ý thức).

## 9. Request latency tăng
- **Debug**: tách `total_time_ms` thành `requestqueue_time_ms` (thread pool bão hoà), `local_time_ms` (disk/append), `remote_time_ms` (chờ follower — replication/network), `responsequeue_time_ms`, `responsesend_time_ms` (network/client chậm đọc).
- [lab failures/network_delay] thêm 200ms trễ trên kafka-1: produce p99 22ms → 2.485s.

## 10. Network bottleneck
- **Metrics**: bytes in/out + replication bytes vs NIC; `responsesend_time`; cross-AZ traffic.
- **Remediation**: compression (giảm ×3–5, performance D), follower fetching cùng rack (KIP-392), thêm broker, quota.

## 11. Hot partition
- **Symptoms**: một partition lag, một consumer CPU cao, các consumer khác rảnh; một broker nhiều bytes in hơn.
- **Debug**: `kcli stats -topic T` (lab 12: P5 83.5%, max/avg=5.01), lag per partition, `consumed_total` theo partition.
- **Remediation**: đổi key (key tổ hợp), salting (`key#n`, mất ordering toàn cục của key — và với ít salt có thể vẫn lệch: lab 12 thấy 8 salt chỉ rơi vào 3 partition), xử lý hot key riêng, tăng partition không giúp nếu 1 key.

## 12. Slow consumer
- Lab 17: consumer 430 msg/s vs producer 5000 msg/s → lag 137k. Xem mục 1. Thêm: đảm bảo retention > thời gian bắt kịp tệ nhất.

## 13. Large message
- **Symptoms**: `MESSAGE_TOO_LARGE`, `RecordTooLarge` phía client, consumer kẹt (client cũ với fetch size nhỏ).
- **Debug**: lab 18 — client limit (batch.max.bytes) chặn trước; broker/topic `max.message.bytes` chặn sau.
- **Remediation**: claim-check pattern (object storage + pointer), chunking, compression; tăng limit có chủ đích ở topic + producer + consumer + `replica.fetch.max.bytes`.

## 14. GC / memory
- **Symptoms**: ISR flapping, session timeout, quorum re-election [gặp trong lab: VM stall ~3s → controller resign, bầu lại epoch 2].
- **Metrics**: `jvm_gc_collection_seconds`, heap used, `newactivecontrollerscount`.
- **Remediation**: heap 4–8GB là đủ cho broker (để RAM cho page cache), G1/ZGC, tách controller.

## 15. Disk I/O saturation
- **Symptoms**: `local_time_ms` Produce cao, `requesthandler idle` thấp, consumer đọc dữ liệu cũ làm chậm cả producer (page cache bị đẩy ra).
- **Remediation**: disk nhanh hơn/JBOD nhiều disk, tách workload replay lớn sang cluster khác, quotas, tiered storage.

## 16. [gặp trong lab] Broker không hồi phục sau restart do IP đổi
- **Symptoms**: sau khi stop/start 2 broker, `kcli brokers` hiện voter 1 `LogEndOffset -1`, 118 partition under-replicated kéo dài > 5 phút; kafka-1 log liên tục `Transitioning to Prospective state due to fetch timeout`, `Voter key ... didn't match`.
- **Cause**: Docker cấp lại IP khác (thậm chí hoán đổi IP giữa kafka-2 và kafka-3) sau restart; broker giữ địa chỉ cũ của peer.
- **Fix**: IP tĩnh cho broker (`ipv4_address` trong compose, subnet cố định) — production: DNS/hostname ổn định, không dựa vào IP động.

## 17. [gặp trong lab] Host port bị chặn
- Port 8021 trên host: TCP connect được nhưng HTTP bị reset (phần mềm trên host chặn) dù container healthy. Kiểm tra từ trong docker network (`docker compose exec toolbox wget ...`) để khoanh vùng; đổi port (payment-consumer chuyển sang 8025).

## Bộ lệnh debug nhanh

```bash
./scripts/cluster-health.sh
docker compose exec toolbox kcli brokers | kcli topics | kcli groups | kcli group -group G
docker compose exec kafka-1 kt kafka-topics --bootstrap-server kafka-1:29092 --describe --under-replicated-partitions
docker compose exec kafka-1 kt kafka-consumer-groups --bootstrap-server kafka-1:29092 --describe --all-groups
docker compose logs kafka-1 | grep -E "ERROR|WARN" | tail
curl -s localhost:7071/metrics | grep -E "underreplicated|offline|activecontroller"
```
