# 25 — Large messages

> Lab: [18_large_messages](../labs/18_large_messages)

## Các giới hạn (phải khớp nhau trên cả đường đi)

| Nơi | Config | Mặc định | Ý nghĩa |
|---|---|---|---|
| Producer | `max.request.size` (Java) / `ProducerBatchMaxBytes` (franz-go, 1MB) | 1 MB | record/batch lớn hơn bị **client** từ chối, không gửi |
| Broker | `message.max.bytes` | ~1 MB (1048588) | batch lớn nhất broker nhận |
| Topic | `max.message.bytes` | = broker | ghi đè theo topic |
| Replication | `replica.fetch.max.bytes` | 1 MB | follower fetch (từ KIP-74 vẫn lấy được batch to hơn) |
| Consumer | `max.partition.fetch.bytes`, `fetch.max.bytes` | 1 MB / 50 MB | là "mềm": luôn trả ít nhất batch đầu tiên dù lớn hơn (KIP-74) |
| Socket | `socket.request.max.bytes` | 100 MB | trần một request |

Lab 18 (dữ liệu thật):
```text
1. 2MB, client batch max 1MB  -> FAILED: MESSAGE_TOO_LARGE ... (uncompressed_bytes=2097158)   # chặn ở client
2. 2MB, client 10MB           -> FAILED: MESSAGE_TOO_LARGE ... (compressed_bytes=2097171)     # broker trả lỗi (topic 1048588)
3. topic max.message.bytes=5MB -> OK: partition=1 offset=0 ; consumer đọc được
4. 3MB chia 12 chunk × 256KB, cùng key -> cùng partition P0 offset 0..11 -> reassembled, sha256 match=true
```

## Vì sao không nên đẩy file lớn vào Kafka

- Record lớn chiếm page cache, đẩy dữ liệu nóng ra → consumer khác chậm.
- Một request lớn giữ network/I/O thread lâu → tăng latency cho mọi client (head-of-line).
- Replication × RF, retention × kích thước → disk tăng nhanh.
- Batch lớn làm producer/consumer tốn heap; lỗi một record lớn = retry cả batch lớn.

## Pattern khuyến nghị: Claim check

```text
Producer ──upload──► Object Storage (S3/GCS/MinIO)  s3://bucket/invoices/2026/10/inv-123.pdf
   │
   └──► Kafka message (nhỏ):  {"invoice_id":"inv-123","uri":"s3://...","size":3145728,"sha256":"...","content_type":"application/pdf"}
Consumer ──đọc message──► tải object khi cần (presigned URL), kiểm tra sha256
```
Lưu ý: vòng đời object (lifecycle) ≥ retention topic; quyền truy cập object; object ghi *trước* khi publish message.

## Chunking (khi buộc phải đi qua Kafka)

Header mỗi chunk: `chunk_id`, `chunk_index`, `total_chunks`, `sha256` (lab dùng đúng các header này); **cùng key** → cùng partition → đúng thứ tự.

Trade-off:
- Consumer phải buffer & reassemble; chunk xen kẽ giữa nhiều file trong cùng partition.
- Một chunk lỗi/thiếu → cả file hỏng; cần timeout + dọn buffer.
- Commit offset chỉ khi cả file hoàn tất (hoặc lưu tiến độ ngoài).
- Retention có thể xoá chunk đầu khi chunk cuối còn → file không thể ghép.
- Producer crash giữa chừng → chunk mồ côi (dùng transaction để ghi cả chunk nguyên tử).

## Nếu thật sự cần message vài MB
Tăng đồng bộ: topic `max.message.bytes`, producer max request, `replica.fetch.max.bytes`, consumer fetch size; bật compression; tách topic riêng cho payload lớn để không ảnh hưởng topic nóng.

## INTERVIEW
1. Kể các giới hạn kích thước trên đường đi của message.
2. Claim-check pattern là gì?
3. Rủi ro của chunking?
