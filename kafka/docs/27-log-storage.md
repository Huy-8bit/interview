# 27 — Log storage: Topic → Partition → Log → Segment → Index

> Lab: [02_partitions](../labs/02_partitions), [13_retention](../labs/13_retention)

```text
Topic orders
  └── Partition orders-0   (một thư mục trên MỖI broker giữ replica)
        └── Log = dãy segment theo offset
              ├── 00000000000000000000.log        segment 1 (đã đóng)
              ├── 00000000000000000000.index
              ├── 00000000000000000000.timeindex
              ├── 00000000000000524000.log        segment 2 (active - đang append)
              ├── 00000000000000524000.index
              ├── 00000000000000524000.timeindex
              ├── 00000000000000524000.snapshot   producer state (idempotence)
              ├── leader-epoch-checkpoint
              └── partition.metadata              (topic_id)
```
Tên file = **base offset** của segment (20 chữ số).

## `.log` — append-only RecordBatch

Mỗi `.log` là chuỗi **RecordBatch** (format v2):
```text
baseOffset | batchLength | partitionLeaderEpoch | magic=2 | crc | attributes(compression, transactional, control)
| lastOffsetDelta | baseTimestamp | maxTimestamp | producerId | producerEpoch | baseSequence | recordCount
| records[] : (length, attributes, timestampDelta, offsetDelta, key, value, headers[])
```
Thấy trực tiếp (lab 02, `kafka-dump-log --print-data-log`):
```text
baseOffset: 0 lastOffset: 0 count: 1 baseSequence: 0 lastSequence: 0 producerId: 2000 producerEpoch: 0
partitionLeaderEpoch: 3 isTransactional: false isControl: false ...
| offset: 0 CreateTime: 1790847361872 keySize: 18 valueSize: 253 sequence: 0 headerKeys: [event_type,producer]
  key: order-4f48ca4c2a78 payload: {"event_id":"4472a4da-...","event_type":"OrderCreated",...}
```
Nén áp dụng cho **cả batch** (records[] được nén). Broker giữ nguyên batch như producer gửi (không giải nén lại nếu codec khớp) → zero-copy khi gửi cho consumer.

## `.index` — offset index (thưa)

Map `relative offset → byte position` cho **khoảng mỗi `index.interval.bytes` (4KB)**. Đọc offset X: binary search trong index tìm entry ≤ X → seek tới vị trí → scan tuần tự tới X. File được pre-allocate (`segment.index.bytes`, 10MB) — thấy trong lab: `.index` của active segment 10485760 bytes, segment đã đóng bị cắt về kích thước thật (0 byte nếu segment quá nhỏ).

## `.timeindex` — timestamp index

Map `timestamp → offset` (cũng thưa). Dùng cho `offsetsForTimes` (consumer seek theo thời gian, `--reset-offsets --to-datetime` ở lab 07) và retention theo thời gian.

## Ghi và đọc diễn ra thế nào

- Append: ghi vào cuối active segment qua page cache; flush xuống disk do OS quyết định (`log.flush.*` mặc định không ép fsync — durability đến từ **replication**, không phải fsync).
- Roll: active segment đóng khi đạt `segment.bytes` (1GB mặc định), `segment.ms` (7 ngày), hoặc index đầy.
- Đọc: tìm segment bằng base offset (skiplist trong bộ nhớ) → index → scan → `sendfile`.
- Xoá: retention/compaction thao tác theo segment (lab 13: `*.deleted` rồi xoá thật sau `file.delete.delay.ms`).

## Vì sao thiết kế này nhanh

- Ghi tuần tự, không update tại chỗ → tốt cho mọi loại disk.
- Index thưa → nhỏ, nằm trong RAM.
- Page cache: dữ liệu mới ghi thường được consumer đọc ngay từ RAM.
- Mỗi segment = 3 file mở → nhiều partition × nhiều segment = nhiều file handle (lab: 335 fd trên kafka-1) → production đặt `ulimit -n` cao (≥100k).

## INTERVIEW

1. Topic, partition, log, segment liên hệ thế nào trên disk?
2. Kafka tìm record ở offset X thế nào?
3. Vì sao index là "sparse"?
4. Kafka có fsync mỗi message không? Durability đến từ đâu?
