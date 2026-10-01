# Lab 13 — Retention theo thời gian (segment-level)

**Mục tiêu**: thấy retention xoá cả segment, log start offset nhảy, file `.deleted`, consumer "from beginning" bắt đầu ở offset mới.
**Đọc trước**: [docs/18](../../docs/18-retention-compaction.md), [docs/27](../../docs/27-log-storage.md)
Topic `retention-demo`: retention.ms=60000, segment.ms=10000, segment.bytes=1MB (chỉ dùng cho lab).

## Chạy
```bash
./labs/13_retention/run.sh     # ~2 phút
```

## Quan sát (kết quả thật)
```text
3 batch × 1500 record cách nhau 12s -> segment 00000000000000009002.log, ...10502.log, ...
+5s..+20s earliest offset = 9002
+25s      earliest offset = 10502       <- segment batch 1 bị xoá (~60s sau record cuối)
UnifiedLog ... Incremented log start offset to ... due to segment deletion
*.log.deleted / *.index.deleted -> xoá thật sau file.delete.delay.ms (5s)
```

## Câu hỏi
1. Vì sao record có thể sống lâu hơn retention.ms?
2. Active segment có bị xoá không?
3. Consumer đang ở offset 9500 khi segment bị xoá thì sao?
