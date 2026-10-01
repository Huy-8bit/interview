# 09 — Rebalancing

> Lab: [06_rebalancing](../labs/06_rebalancing) (5 phần A–E), [failures/consumer_rebalance](../labs/failures/consumer_rebalance)

## WHAT

Rebalance = group tính lại "partition nào thuộc member nào". Xảy ra khi:
- member join (scale up, restart) / leave (LeaveGroup khi shutdown sạch)
- member bị coi là chết (không heartbeat trong `session.timeout.ms`) hoặc quá chậm (`max.poll.interval.ms`)
- subscription đổi (topic mới khớp regex, số partition tăng)

## HOW — timeline đo được trong lab (traffic 50 msg/s, 3 consumer, cooperative-sticky)

### A. Graceful stop (SIGTERM → commit → LeaveGroup)
```text
09:58:11.742  docker stop order-consumer-2
              order-consumer-2: shutdown -> revoked "orders[P1 P4]" -> left group cleanly
              order-consumer-1: assigned newly_assigned=orders[P1]  now_owns=orders[P0 P1 P3]
              order-consumer-3: assigned newly_assigned=orders[P4]  now_owns=orders[P2 P4 P5]
>>> orphaned partitions re-assigned 478 ms after docker stop
```

### B. Crash (SIGKILL — không có LeaveGroup)
```text
09:58:44.179  kill -9 order-consumer-2
+5s           group vẫn Stable, order-consumer-2 vẫn "sở hữu" P3 P5:
                orders 3  COMMITTED 1371  LOG-END 1417  LAG 46   order-consumer-2
                orders 5  COMMITTED 1312  LOG-END 1361  LAG 49   order-consumer-2
>>> partitions re-assigned 10644 ms after the crash   (session.timeout.ms = 10s)
```
Trong 10.6s đó **không ai xử lý** P3/P5 → lag và end-to-end latency của các key thuộc hai partition này tăng.

### A2. Member join lại (cooperative = 2 vòng)
```text
vòng 1: order-consumer-1 revoked=orders[P3]   order-consumer-3 revoked=orders[P5]   (nhả phần sẽ chuyển)
vòng 2: order-consumer-2 assigned "orders[P3 P5]"                                   (nhận)
          member khác giữ nguyên P0 P1 / P2 P4 suốt quá trình
```

### C vs D vs E — protocol
| | Eager (range/roundrobin/sticky) | Cooperative-sticky | KIP-848 (consumer protocol) |
|---|---|---|---|
| Revoke | **tất cả** partition của **mọi** member | chỉ partition cần chuyển | chỉ partition cần chuyển, từng member |
| Barrier toàn group | Có (stop-the-world) | Có nhưng member vẫn xử lý partition giữ lại | Không |
| Số vòng | 1 | 2 | Liên tục hội tụ qua heartbeat |
| Ai tính assignment | leader client | leader client | broker |
| Lab | survivors revoke cả phần của mình | 0 revoke ở survivors | `protocol=consumer (KIP-848)` |

## Consumer pause & rebalance duration — vì sao quan trọng

Trong eager rebalance, *mọi* partition dừng xử lý từ lúc revoke tới lúc assign + thời gian khởi tạo (load state, cache warm-up). Với hàng trăm partition và consumer có state (Kafka Streams), mỗi lần deploy rolling 20 instance = 20 lần stop-the-world. Cooperative/KIP-848 + static membership giảm điều này về gần 0.

## Đảm bảo đúng khi rebalance

1. **Commit trước khi mất partition**: Runner commit `pending` trong `OnPartitionsRevoked` (manual mode).
2. **Không xử lý dở khi bị revoke**: `BlockRebalanceOnPoll` → rebalance chỉ diễn ra sau khi batch xử lý & commit xong → không có cửa sổ "đã revoke nhưng vẫn xử lý".
3. **Lost ≠ revoked**: `OnPartitionsLost` (session hết hạn / bị fence) → **không** commit (member khác có thể đã nhận partition) — chấp nhận duplicate.
4. Xử lý batch phải < rebalance timeout / max poll interval, nếu không member bị loại → rebalance storm.

## FAILURE patterns

| Pattern | Nguyên nhân | Cách nhận biết |
|---|---|---|
| Rebalance storm | processing > max.poll.interval; GC; CPU throttling | `rebalance_events_total` tăng liên tục, lag dao động |
| Rebalance kéo dài 45s | member chết/ghost giữ chỗ tới session timeout | coordinator log `has failed, removing it` |
| Duplicate sau mỗi deploy | không commit khi revoke / commit async bị mất | duplicate_skipped_total tăng theo deploy |
| Idle consumer | consumer > partition | `kcli group` hiện IDLE |

## PRODUCTION

- Classic: `partition.assignment.strategy=CooperativeStickyAssignor`; Kafka ≥4.0: cân nhắc `group.protocol=consumer`.
- `session.timeout.ms` 10–45s tuỳ yêu cầu phát hiện lỗi vs độ nhạy với GC.
- Static membership cho rolling restart.
- Graceful shutdown + `terminationGracePeriodSeconds` đủ lâu.

## DEBUG

```bash
PARTS="A B" ./labs/06_rebalancing/run.sh
docker compose logs -f order-consumer-1 order-consumer-2 order-consumer-3 | grep REBALANCE
docker compose logs kafka-1 kafka-2 kafka-3 | grep -E "Preparing to rebalance|Stabilized group" | grep order-processing
```
Grafana > Consumer Performance > "Rebalance callbacks", "Assigned partitions per instance".

## INTERVIEW

1. Liệt kê nguyên nhân gây rebalance.
2. Vì sao kill -9 consumer làm rebalance chậm hơn docker stop? Con số trong lab?
3. Eager vs cooperative vs KIP-848?
4. Làm sao tránh duplicate khi rebalance?
5. Rebalance storm là gì, debug thế nào?
