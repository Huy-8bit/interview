# Lab 14 — Log compaction & tombstone

**Mục tiêu**: user-1 v1,v2,v3 → chỉ còn v3; tombstone xoá key; offset có lỗ.
**Đọc trước**: [docs/18](../../docs/18-retention-compaction.md)
Topic `user-profile-compacted`: cleanup.policy=compact, segment.ms=15000, min.cleanable.dirty.ratio=0.01, delete.retention.ms=20000.

## Chạy
```bash
./labs/14_compaction/run.sh    # ~2–3 phút
curl -s -XPUT localhost:8000/users/42/profile -d '{"name":"An","email":"an@x","tier":"gold"}'   # tay: ghi user-events + compacted
curl -s -XDELETE localhost:8000/users/42/profile                                               # tombstone
```

## Quan sát (kết quả thật)
```text
trước: P0 @0 user-1 v1 | @1 v2 | @2 v3 | @3 user-3 v1 | @4 user-3 null
+15s sau khi roll segment: records with key user-1: 1 -> P0 @2 v3 ; P0 @4 user-3 null còn
+10s sau delete.retention.ms: records with key user-3: 0
offsets NOT renumbered: P0 @2, @5, @6 ...
```

## Câu hỏi
1. Vì sao phải ghi "filler" mới thấy compaction?
2. Tombstone giữ lại để làm gì?
3. Một consumer đọc topic compacted từ đầu có thấy mọi version không?
