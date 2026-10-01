# Performance lab

**Mục tiêu**: đổi một tham số mỗi lần, cùng workload: partition count, acks, batching, compression, số consumer.
**Đọc trước**: [docs/19](../../docs/19-performance.md)

## Chạy
```bash
./labs/performance/run.sh                      # ~4 phút, ghi kết quả vào labs/performance/last-run.txt
RECORDS=200000 PARTS="C D" ./labs/performance/run.sh
```
Công cụ: `kcli bench-produce` (throughput, p50/p99 per record, batches, bytes on wire, compression ratio, CPU client) và `kcli bench-consume` (N consumer trong một group, work giả lập mỗi record).

## Kết quả thật (laptop, 3 broker một VM, 100k × 1KB JSON) — xem `last-run.txt`
```text
A1 partitions 1/3/6/12 (producer): 463k / 591k / 486k / 268k rec/s   (12 partition: batch nhỏ 314 rec)
A2 partitions 1/3/6/12 (consumers=partitions, 1ms work): 380 / 1139 / 2150 / 4588 rec/s
B  acks 0/1/all: 654k / 474k / 584k rec/s  -> khác biệt trong nhiễu trên loopback (xem docs/19)
C  linger0+16KB: 67k rec/s p50 261ms ; linger5ms+1MB: 284k ; linger20ms+1MB: 336k
D  none/gzip/snappy/lz4/zstd: ratio 1.00/5.07/4.14/2.93/5.41 ; zstd nhanh nhất ở lab này
E  consumers 1/2/3/6/8 trên 6 partition: 379/749/1109/2298/2386 rec/s ; 8 consumer -> 2 IDLE
```

## Câu hỏi
1. Vì sao số liệu producer không tăng theo số partition?
2. Vì sao không kết luận "acks=all nhanh hơn acks=1" từ bảng B?
3. Nếu chạy trên 3 máy thật qua mạng 1Gbps, bảng D thay đổi thế nào?
