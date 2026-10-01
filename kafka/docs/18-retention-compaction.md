# 18 — Retention & Log Compaction

> Lab: [13_retention](../labs/13_retention), [14_compaction](../labs/14_compaction) · Storage internals: [27-log-storage](27-log-storage.md)

## Retention (cleanup.policy=delete)

Kafka xoá **cả segment**, không xoá từng record. Một segment *đã đóng* bị xoá khi:
- `retention.ms`: timestamp lớn nhất trong segment cũ hơn now − retention.ms, **hoặc**
- `retention.bytes`: tổng kích thước partition vượt ngưỡng → xoá segment cũ nhất.

Segment đang ghi (**active segment**) không bao giờ bị xoá; nó được "roll" (đóng, mở segment mới) khi đạt `segment.bytes` hoặc `segment.ms` (và có record mới tới). Thread kiểm tra chạy mỗi `log.retention.check.interval.ms`.

Lab 13 (`retention-demo`: retention.ms=60s, segment.ms=10s, segment.bytes=1MB, check 10s):
```text
3 batch × 1500 record, cách nhau 12s -> mỗi batch một segment:
493887  00000000000000009002.log      (batch 1)
493887  00000000000000010502.log      (batch 2)
...
+5s..+20s earliest offset = 9002
+25s      earliest offset = 10502        <- segment batch 1 bị xoá ~60s sau record cuối của nó
broker: Incremented log start offset to ... due to segment deletion
        Deleting segment LogSegment(baseOffset=...)   -> file đổi tên *.deleted, xoá thật sau file.delete.delay.ms
```
Hệ quả: retention thực tế = retention.ms + tới một `segment.ms`/`segment.bytes` + chu kỳ check. Consumer có committed offset < log start → `OFFSET_OUT_OF_RANGE` → reset theo `auto.offset.reset`.

## Log compaction (cleanup.policy=compact)

Giữ **ít nhất bản ghi mới nhất cho mỗi key**; các bản cũ hơn của cùng key bị xoá dần. Dùng cho *state*: "giá trị hiện tại của user-1 là gì".

```text
trước compaction (partition 0):
 @0 user-1 v1   @1 user-1 v2   @2 user-1 v3   @3 user-3 v1   @4 user-3 null(tombstone)
sau compaction:
 @2 user-1 v3   @4 user-3 null              (offset giữ nguyên -> có "lỗ")
sau delete.retention.ms (tombstone hết hạn) + lần clean tiếp theo:
 @2 user-1 v3                               (user-3 biến mất hoàn toàn)
```
Đây chính xác là output lab 14:
```text
+15s records with key user-...-1 still in the log: 1      (v3 còn lại)
+10s records with key user-...-3: 0                        (value + tombstone đã bị xoá)
offsets are NOT renumbered: P0 @2, P0 @5, P0 @6 ...
```

### Cơ chế (log cleaner)
- Log chia thành phần **clean** (đã compact) và **dirty** (phần đuôi chưa compact). Cleaner chọn partition có `dirty ratio` > `min.cleanable.dirty.ratio` (lab 0.01, mặc định 0.5).
- Chỉ compact **segment đã đóng** → phải roll (lab: chờ `segment.ms`=15s rồi ghi record "filler").
- Cleaner build offset map (key → offset mới nhất) cho phần dirty, rewrite segment bỏ record cũ.
- `min.compaction.lag.ms` (giữ bản cũ tối thiểu bao lâu), `max.compaction.lag.ms` (ép compact sau bao lâu).
- **Tombstone** (key + value null) = lệnh xoá key; được giữ `delete.retention.ms` để consumer đang đọc kịp thấy "đã xoá", rồi bị xoá.
- Record **không có key** không hợp lệ trên topic compacted (broker từ chối; metric `nokeycompactedtopicrecords`).

## delete vs compact vs compact,delete

| Policy | Giữ gì | Use case |
|---|---|---|
| `delete` | Mọi record trong cửa sổ thời gian/kích thước | Event stream: orders, payments, clickstream, log |
| `compact` | Bản mới nhất mỗi key, vô thời hạn | State/changelog: user profile, config, inventory snapshot, KTable changelog, `__consumer_offsets` |
| `compact,delete` | Bản mới nhất mỗi key **và** xoá cả key quá retention | Changelog có giới hạn tuổi: session state, cache có TTL, CDC giữ 7 ngày |

Lab có cặp minh hoạ: `PUT /users/{id}/profile` ghi cùng sự kiện vào `user-events` (delete — lịch sử thay đổi) và `user-profile-compacted` (compact — trạng thái hiện tại); `DELETE` gửi tombstone.

| Use case | Policy | Key |
|---|---|---|
| Event stream nghiệp vụ | delete (7 ngày) | entity id |
| State changelog (Kafka Streams) | compact | state key |
| CDC (Debezium) | compact hoặc compact,delete | primary key |
| Configuration | compact | config name |
| User profile state | compact | user id |

## PRODUCTION / DEBUG

- Retention đặt theo SLA replay + thời gian consumer có thể down + chi phí disk (xem capacity planning).
- Compaction tốn I/O + memory (`log.cleaner.dedupe.buffer.size`); theo dõi `kafka_log_logcleanermanager_uncleanable_partitions_count`, `max-dirty-percent`.
- Không áp config retention ngắn lên topic chính (lab chỉ dùng `retention-demo`).

```bash
./labs/13_retention/run.sh ; ./labs/14_compaction/run.sh
docker compose exec kafka-1 ls -l /var/lib/kafka/data/retention-demo-0/
docker compose exec kafka-1 kt kafka-configs --bootstrap-server kafka-1:29092 --describe --entity-type topics --entity-name user-profile-compacted
```

## INTERVIEW

1. Kafka xoá dữ liệu theo đơn vị gì? Vì sao retention thực tế dài hơn retention.ms?
2. Compaction đảm bảo gì và không đảm bảo gì? (không đảm bảo chỉ còn 1 bản; phần đuôi dirty còn nhiều bản)
3. Tombstone là gì, vì sao cần delete.retention.ms?
4. Chọn cleanup.policy cho: orders, user profile, CDC bảng products.
