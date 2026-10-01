# 26 — `__consumer_offsets`: committed offset thực sự nằm ở đâu

> Lab: [07_offsets](../labs/07_offsets) bước 6

## WHAT

`__consumer_offsets` là topic nội bộ (mặc định **50 partition**, RF=3 trong lab, `cleanup.policy=compact`). Nó lưu:

1. **Offset commit**: key = `(group, topic, partition)`, value = `(offset, leaderEpoch, metadata, commitTimestamp)`.
2. **Group metadata**: key = `group`, value = protocol type, generation, leader, members + assignment (classic), hoặc các record của KIP-848 (ConsumerGroupMetadata, MemberMetadata, TargetAssignment...).

## Group coordinator liên quan thế nào

```text
partition = Utils.abs(group.id.hashCode()) % offsets.topic.num.partitions      (Java String.hashCode)
group coordinator = broker đang là LEADER của partition đó
```
Lab 07:
```text
group lab-07-replay -> __consumer_offsets partition 21 (its leader is the GROUP COORDINATOR of lab-07-replay)
__consumer_offsets  21    kafka-2  kafka-2,kafka-3,kafka-1  kafka-1,kafka-2,kafka-3
{"key":{"type":1,"data":{"group":"lab-07-replay","topic":"orders","partition":0}},
 "value":{"version":4,"data":{"offset":0,"leaderEpoch":-1,"metadata":"","commitTimestamp":1790849105410,...}}}
```

> Bẫy nhỏ đã gặp: công thức dùng **`Utils.abs`** (abs thường), không phải `hash & 0x7fffffff` như partitioner của producer. Dùng nhầm sẽ ra partition 27 thay vì 21.

## HOW — một OffsetCommit

1. Consumer gửi `OffsetCommitRequest(group, generation/memberEpoch, memberId, offsets)` tới coordinator.
2. Coordinator kiểm tra member còn hợp lệ (generation đúng — chống zombie).
3. Ghi record vào partition `__consumer_offsets` của group như một **produce acks=all** (offsets.commit.required.acks = -1, min ISR áp dụng).
4. Cập nhật cache trong bộ nhớ; trả response.
5. Compaction giữ commit mới nhất cho mỗi (group, topic, partition); offset của group rỗng bị xoá sau `offsets.retention.minutes` (7 ngày).

Khi coordinator chết: leader mới của partition đó đọc lại (load) partition → trở thành coordinator mới (log lab: `Loaded classic group notification-group with 1 members`). Trong lúc chuyển, commit/join nhận `COORDINATOR_LOAD_IN_PROGRESS` / `NOT_COORDINATOR` → client retry. Lab ghi nhận một hệ quả: LeaveGroup gửi đúng lúc coordinator đang chuyển bị mất → member cũ thành "ghost" cho tới hết session timeout (45s).

## Hot partition trong `__consumer_offsets`

Group commit càng thường xuyên thì partition của nó càng "nóng". Lab 07:
```text
P14  32693  26.7%   P22  22481  18.4%   P41  62149  50.8%     (các partition khác ~0)
max/avg=25.39  <-- HOT PARTITION
```
Group commit mỗi batch (manual) với hàng nghìn msg/s → hàng chục commit/s → một broker làm coordinator cho nhiều group bận sẽ chịu tải lớn. Giảm tần suất commit (theo thời gian/số record) nếu cần.

## Đọc trực tiếp

```bash
docker compose exec kafka-1 kt kafka-console-consumer --bootstrap-server kafka-1:29092 \
  --topic __consumer_offsets --partition 21 --offset earliest \
  --formatter org.apache.kafka.tools.consumer.OffsetsMessageFormatter --timeout-ms 5000
docker compose exec toolbox kcli stats -topic __consumer_offsets
```
(Kafka 4.x: formatter nằm ở package `org.apache.kafka.tools.consumer`, khác tài liệu cũ `kafka.coordinator.group.GroupMetadataManager$OffsetsMessageFormatter`.)

## INTERVIEW

1. Committed offset lưu ở đâu? Trước Kafka 0.9 lưu ở đâu? (ZooKeeper)
2. Group coordinator được xác định thế nào?
3. Vì sao `__consumer_offsets` là compacted topic?
4. Coordinator chết thì consumer group bị ảnh hưởng gì?
