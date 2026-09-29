# Thiết kế bảng lớn

## 1. Tổng quan

Một bảng 10.000 row tha thứ mọi quyết định thiết kế. Một bảng 500 triệu row — ví dụ lịch sử dịch vụ của 50 triệu xe, hay telemetry từ hàng trăm nghìn thiết bị — biến mỗi quyết định thành chi phí thật: mỗi byte thừa nhân với nửa tỷ, mỗi index thừa là hàng chục GB và chậm mọi lần ghi, mỗi `ALTER TABLE` sai là downtime, mỗi `DELETE` hàng loạt là hàng giờ bloat.

Tài liệu này tổng hợp các quyết định thiết kế cho bảng lớn và lý do đằng sau chúng. Ví dụ xuyên suốt: bảng `service_records` lưu lịch sử bảo dưỡng/sửa chữa cho hệ thống bảo hành xe.

## 2. Mental Model

> Với bảng lớn, câu hỏi không phải "query này có chạy không" mà là "chi phí của nó tỷ lệ với cái gì". Mọi thao tác phải có chi phí tỷ lệ với **lượng dữ liệu cần thiết** (một VIN, một ngày), không phải với **kích thước bảng**.

## 3. Vì sao cần thiết kế riêng?

| Thao tác | Bảng nhỏ | Bảng 500 triệu row |
|---|---|---|
| Seq scan | Vài ms | Hàng chục phút |
| Tạo index | Tức thì | Hàng giờ, cần `CONCURRENTLY` |
| `ALTER TABLE` rewrite | Tức thì | Khóa bảng hàng giờ |
| `DELETE` dữ liệu cũ | Tức thì | Hàng trăm triệu dead tuple, WAL khổng lồ |
| `count(*)` | Tức thì | Hàng phút |
| `OFFSET 1000000` | Chấp nhận được | Đọc và bỏ một triệu row mỗi trang |
| VACUUM | Tức thì | Hàng giờ; ảnh hưởng freeze |

## 4. Quyết định 1: kiểu dữ liệu và kích thước row

Kích thước row ảnh hưởng số row mỗi page → số page phải đọc → hiệu quả cache.

| Quyết định | Gợi ý |
|---|---|
| Khóa chính | `bigint` (8 byte) hoặc UUID (16 byte); tránh `numeric`/`text` làm khóa |
| Thời gian | `timestamptz` (8 byte) |
| Tiền | `numeric(12,2)` hoặc số nguyên theo đơn vị nhỏ nhất (`bigint` đồng) |
| Enum trạng thái | `smallint` hoặc `text` có `CHECK`; enum type khó thay đổi |
| JSON | `jsonb` cho thuộc tính linh hoạt; tách các field được lọc thường xuyên thành cột thật |
| Dữ liệu lớn ít dùng | Tách ra bảng phụ hoặc object storage, giữ tham chiếu |

**Thứ tự cột** ảnh hưởng padding: đặt cột 8 byte trước, rồi 4 byte, rồi 2 byte, rồi kiểu biến độ dài có thể tiết kiệm vài byte mỗi row — nhỏ, nhưng nhân với 500 triệu.

### UUID ngẫu nhiên và index

UUID v4 hoàn toàn ngẫu nhiên: mỗi insert chèn vào vị trí ngẫu nhiên của B-tree → page index được chạm ngẫu nhiên, cache kém, nhiều page split, WAL lớn (full-page writes cho nhiều page khác nhau). Với bảng ghi nhiều, đây là chi phí đáng kể.

Lựa chọn thay thế:

- `bigint` sinh bởi sequence/identity: tăng dần, insert luôn vào cuối index.
- **UUID v7** (có tiền tố thời gian): vẫn là UUID nhưng tăng gần đơn điệu theo thời gian. > **Ghi chú version:** PostgreSQL 18 có hàm `uuidv7()` sẵn; version cũ hơn sinh ở ứng dụng.

## 5. Quyết định 2: index theo access pattern

Liệt kê query thật và tần suất trước khi tạo index:

| Access pattern | Index |
|---|---|
| Lịch sử của một xe, mới nhất trước | `(vin, serviced_at DESC)` |
| Record của một đại lý trong khoảng thời gian | `(dealer_id, serviced_at)` |
| Record chưa đối soát (tập nhỏ) | Partial: `(serviced_at) WHERE reconciled = false` |
| Truy vấn theo khoảng thời gian toàn bảng (báo cáo) | BRIN trên `serviced_at` nếu dữ liệu ghi theo thời gian |
| Tìm theo mã phụ tùng trong JSONB | Expression index trên `(payload->>'part_code')` |

Mỗi index thêm vào là chi phí trên **mọi** insert. Bảng 500 triệu row với 8 index có thể có tổng index lớn hơn bảng. Xem [Index](index.md) và [Các loại index](btree-hash-gin-gist-brin.md).

## 6. Quyết định 3: partitioning và vòng đời dữ liệu

Nếu dữ liệu có tuổi thọ (giữ 10 năm cho dữ liệu tài chính, 13 tháng cho telemetry), partition theo thời gian là lựa chọn tự nhiên: retention bằng `DETACH` + `DROP`, VACUUM theo partition, index partition gần đây nằm trong cache. Xem [Partitioning](partitioning.md).

Nhưng nếu query chính là "lịch sử của một VIN" (không có điều kiện thời gian), partition theo thời gian buộc query quét mọi partition. Cân nhắc:

- Luôn giới hạn thời gian trong query (UI chỉ hiển thị 2 năm gần nhất mặc định).
- Hoặc partition theo hash của VIN (mất lợi ích retention theo thời gian).
- Hoặc tách dữ liệu nóng (2 năm) và dữ liệu lưu trữ (bảng/hệ thống khác).

## 7. Quyết định 4: thay đổi schema trực tuyến

| Thay đổi | Cách an toàn |
|---|---|
| Thêm cột nullable | `ADD COLUMN` — tức thì (chỉ cập nhật catalog) |
| Thêm cột có default hằng số | Tức thì từ PostgreSQL 11 |
| Thêm `NOT NULL` | Thêm `CHECK (col IS NOT NULL) NOT VALID`, backfill, `VALIDATE CONSTRAINT` (không khóa ghi), rồi `SET NOT NULL` (12+ dùng constraint đã validate để bỏ qua scan) |
| Thêm foreign key | `ADD CONSTRAINT ... NOT VALID`, sau đó `VALIDATE CONSTRAINT` |
| Tạo index | `CREATE INDEX CONCURRENTLY` |
| Đổi kiểu cột (rewrite) | Thêm cột mới, backfill theo lô, chuyển đổi ứng dụng, bỏ cột cũ (expand/contract) |
| Đổi tên cột | Expand/contract để ứng dụng cũ và mới cùng chạy |

Mọi migration: `SET lock_timeout` ngắn, retry. Xem [Locks](locks.md#5-bên-trong-hệ-thống-xảy-ra-gì-alter-table-làm-đứng-service).

## 8. Quyết định 5: backfill và thao tác hàng loạt

```python
async def backfill_region(session_factory, batch_size: int = 5_000):
    last_id = 0
    while True:
        async with session_factory() as session, session.begin():
            result = await session.execute(
                text("""
                    UPDATE service_records s
                    SET region = d.region
                    FROM dealers d
                    WHERE s.dealer_id = d.id
                      AND s.id > :last_id AND s.id <= :last_id + :batch
                      AND s.region IS NULL
                """),
                {"last_id": last_id, "batch": batch_size},
            )
        last_id += batch_size
        if last_id > await max_id(session_factory):
            break
        await asyncio.sleep(0.05)     # nhường tài nguyên cho traffic thật
```

- Chia theo **khoảng khóa chính**, không dùng `OFFSET`.
- Mỗi batch một transaction ngắn: lock ngắn, WAL chia nhỏ, replication không bị dồn.
- Nghỉ giữa các batch; theo dõi replication lag và dừng nếu vượt ngưỡng.
- Idempotent (`AND region IS NULL`): chạy lại an toàn nếu bị gián đoạn.
- Lưu checkpoint (`last_id`) để tiếp tục sau khi dừng.

## 9. Quyết định 6: đọc dữ liệu lớn

- **Pagination**: keyset (`WHERE (serviced_at, id) < (...)`) thay vì `OFFSET`. Xem [Pagination](../08-api-design/pagination.md).
- **Đếm**: hiển thị con số ước tính (`reltuples`), hoặc duy trì bảng đếm; tránh `count(*)` chính xác trên toàn bảng ở request người dùng.
- **Export**: stream bằng server-side cursor theo batch, hoặc chạy job nền ghi ra object storage.
- **Báo cáo tổng hợp**: bảng tổng hợp cập nhật định kỳ/incremental, materialized view, hoặc hệ thống phân tích riêng (data warehouse) nhận dữ liệu qua CDC.

## 10. Quyết định 7: update và hot row

- Bảng lịch sử nên là **append-only** khi có thể: sửa bằng cách thêm record mới (event) thay vì update. Append-only cho phép BRIN, giảm dead tuple, dễ audit.
- Cột được update thường xuyên (trạng thái xử lý) nên nằm ở bảng nhỏ riêng, tách khỏi bảng lịch sử lớn.
- Với bảng có update, `fillfactor` 80–90 để HOT update có chỗ; tránh index trên cột bị update.

## 11. Bên trong hệ thống xảy ra gì khi bảng tăng 100 lần?

| Kích thước | Điều thay đổi |
|---|---|
| 5 triệu row | Mọi thứ vẫn nằm trong cache; thiếu index vẫn ổn |
| 50 triệu row | Index không phù hợp lộ rõ; `OFFSET` chậm; VACUUM bắt đầu đáng kể |
| 500 triệu row | Index không còn vừa hết trong RAM; mỗi cache miss là I/O; thay đổi schema cần kế hoạch; autovacuum mặc định quá chậm |
| 5 tỷ row | Partitioning gần như bắt buộc; retention phải tự động; freeze/wraparound cần giám sát chặt; cân nhắc tách hệ thống |

## 12. Failure Modes

| Failure | Nguyên nhân | Dấu hiệu |
|---|---|---|
| Downtime khi migration | `ALTER TABLE` rewrite hoặc chờ lock | Service đứng khi deploy |
| Replication lag lớn | Backfill/DELETE một transaction khổng lồ | Replica tụt hàng giờ |
| Bloat | Update nhiều trên bảng lớn, autovacuum chậm | Kích thước tăng nhanh hơn dữ liệu |
| Insert chậm dần | Quá nhiều index, UUID ngẫu nhiên | Latency ghi tăng theo kích thước bảng |
| Query chậm dần | Index không còn nằm trong cache | Cache hit ratio giảm |
| Wraparound | Freeze không theo kịp bảng lớn | Cảnh báo tuổi XID |

## 13. Trade-offs

| Lựa chọn | Lợi ích | Chi phí |
|---|---|---|
| Append-only | Ít bloat, audit tốt, BRIN | Đọc trạng thái hiện tại cần tổng hợp |
| JSONB linh hoạt | Schema thay đổi dễ | Lớn hơn, khó index, thống kê kém |
| Cột thật | Nhỏ gọn, thống kê tốt | Thay đổi schema cần migration |
| `bigint` identity | Nhỏ, index tuần tự | Lộ số lượng, cần điều phối khi merge dữ liệu |
| UUID v7 | Sinh phân tán, index gần tuần tự | 16 byte |

## 14. Sai lầm thường gặp

- Thiết kế bảng theo "đối tượng" mà không liệt kê access pattern.
- Dùng UUID v4 làm khóa chính cho bảng ghi rất nhiều.
- `DELETE` dữ liệu cũ thay vì partition.
- Backfill trong một transaction.
- Để mọi cột có index "phòng khi cần".
- Đặt cột trạng thái update liên tục trong bảng lịch sử lớn.

## 15. Cách debug

```sql
-- Kích thước bảng, index, TOAST
SELECT pg_size_pretty(pg_relation_size('service_records')) AS heap,
       pg_size_pretty(pg_indexes_size('service_records')) AS indexes,
       pg_size_pretty(pg_total_relation_size('service_records')) AS total;

-- Ước tính số row không cần count(*)
SELECT reltuples::bigint FROM pg_class WHERE relname = 'service_records';
```

Theo dõi xu hướng: kích thước theo tuần, tỷ lệ index/heap, dead tuple, tuổi XID, cache hit.

## 16. Best Practices

- Bắt đầu từ access pattern và vòng đời dữ liệu.
- Kiểu dữ liệu gọn; tách dữ liệu lớn ít dùng.
- Index tối thiểu phục vụ query thật; BRIN cho cột thời gian của bảng append-only.
- Partition theo thời gian khi có retention.
- Mọi thay đổi schema theo expand/contract với `lock_timeout`; mọi backfill theo lô idempotent.
- Keyset pagination; không đếm chính xác trên request người dùng.
- Điều chỉnh autovacuum theo bảng; giám sát freeze.

## 17. Tóm tắt

- Với bảng lớn, mọi thao tác phải có chi phí tỷ lệ với dữ liệu cần thiết, không với kích thước bảng.
- Kiểu dữ liệu, thứ tự cột, và loại khóa chính ảnh hưởng trực tiếp tới kích thước và hiệu năng ghi.
- Index theo access pattern; mỗi index là chi phí trên mọi lần ghi.
- Partition theo thời gian cho retention; thay đổi schema và backfill phải trực tuyến, theo lô.
- Ưu tiên append-only và tách dữ liệu nóng/lạnh.

## Liên quan

- [Index](index.md)
- [Partitioning](partitioning.md)
- [VACUUM và Bloat](vacuum-bloat.md)
- [Locks](locks.md)
- [Query Optimization](query-optimization.md)
- [Design Vehicle Warranty](../11-system-design/design-vehicle-warranty.md)
