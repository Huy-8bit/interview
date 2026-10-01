# Failure: Hot partition

**Đọc**: [docs/21 §11](../../../docs/21-production-troubleshooting.md)

## Chạy
```bash
./labs/failures/hot_partition/run.sh  (= labs/12_hot_partition)
```

## Điều xảy ra
80% traffic một key → một partition → một consumer quá tải.

## Quan sát (kết quả thật khi xây lab)
```text
P5 83.5%, lag 4753; P0 lag 122 do head-of-line
```

## Câu hỏi
Bạn sẽ đổi key thế nào cho flash sale một sản phẩm?

Sau lab: `./scripts/reset-lab.sh`.
