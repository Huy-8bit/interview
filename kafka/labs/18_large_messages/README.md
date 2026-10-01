# Lab 18 — Large messages

**Mục tiêu**: thấy giới hạn phía client, phía broker/topic, nâng giới hạn, và chunking.
**Đọc trước**: [docs/25](../../docs/25-large-messages.md)

## Chạy
```bash
./labs/18_large_messages/run.sh
```

## Quan sát (kết quả thật)
```text
max.message.bytes=1048588
2MB, client max 1MB  -> FAILED: MESSAGE_TOO_LARGE ... (uncompressed_bytes=2097158)          (client)
2MB, client max 10MB -> FAILED: MESSAGE_TOO_LARGE ... (compressed_bytes=2097171)           (broker)
topic max.message.bytes=5242880 -> OK: partition=1 offset=0 ; consumer đọc được 1 record
3MB / 256KB chunk -> 12 chunk P0 offset 0..11 -> reassembled 12 chunks, 3145728 bytes, sha256 match=true
```

## Câu hỏi
1. Những config nào phải đổi cùng lúc để cho phép message 5MB?
2. Vì sao claim-check tốt hơn chunking trong đa số trường hợp?
