# Go data generator

Bản Go độc lập cho schema e-commerce hiện tại. Lệnh Python cũ được giữ nguyên.
**Bản Go chỉ nạp vào DB mới, đã có schema/index và chưa có data/identity đã dùng.**
DB đang có dữ liệu sẽ bị từ chối trước mọi thay đổi. Không có chế độ reset, truncate,
xóa DB hay append; không tự động sửa/xóa một lần nạp dở.

## Chạy thử mà không kết nối DB

```bash
# Chạy bằng Docker, không khởi động/recreate các service PostgreSQL
./scripts/generate-data-go.sh 5m --dry-run --data-now 2026-10-01T00:00:00Z

# Có Go >= 1.25 trên host: bỏ qua build image Docker
./scripts/generate-data-go.sh --local 5m --dry-run --workers 4 \
  --data-now 2026-10-01T00:00:00Z
```

`--dry-run` thực sự sinh và mã hóa toàn bộ COPY payload trong RAM, rồi bỏ từng
batch; không lưu file dung lượng lớn và không mở kết nối PostgreSQL. Kết quả đo
không bao gồm COPY vào server, tạo index, WAL, đĩa hay streaming replication.

## Nạp vào một database mới

DB chính của dự án là **`ecommerce`**. Khi các bảng đã trống và identity đã reset
(hoặc vừa khởi tạo cluster/schema), nạp trực tiếp bằng:

```bash
DB_NAME=ecommerce ./scripts/generate-data-go.sh 5m --bulk-load --analyze --batch-size 50000
```

Không đặt `DB_NAME=ecommerce_go` nếu chưa tạo database đó. Biến `DB_NAME` chỉ
chọn DB đích, không tạo database. Chương trình in DB đích khi kết nối và giữ lại
lỗi PostgreSQL/SQLSTATE để phân biệt DB không tồn tại, sai mật khẩu và lỗi mạng.
Bản Go vẫn từ chối nếu bảng còn dữ liệu; không tự truncate hay xóa database.

Nếu đã có DB riêng với schema hiện tại:

```bash
DB_NAME=ecommerce_go ./scripts/generate-data-go.sh 5m --bulk-load --analyze
```

Ví dụ tạo **DB mới tên `ecommerce_go`**, giữ nguyên `ecommerce` đang sử dụng
(user `postgres` dưới đây là mặc định của dự án; thay nếu bạn đã cấu hình khác):

```bash
(
  set -e
  docker compose exec -T postgres-primary createdb -U postgres ecommerce_go
  for sql in postgres/primary/init/02-extensions.sql \
             postgres/primary/init/03-schema.sql \
             postgres/primary/init/04-indexes.sql; do
    docker compose exec -T postgres-primary psql -X -v ON_ERROR_STOP=1 \
      -U postgres -d ecommerce_go < "$sql"
  done
  DB_NAME=ecommerce_go ./scripts/generate-data-go.sh 5m --bulk-load --analyze
)
```

`createdb` sẽ báo lỗi nếu tên DB đã tồn tại; không có lệnh xóa/recreate ở đây.
DB mới vẫn dùng chung tài nguyên cluster và tạo WAL cho replica; muốn đo biệt lập
hãy trỏ `DB_HOST`, `DB_PORT`, `DB_NAME` tới PostgreSQL riêng. Với `--local`, mặc
định là `localhost:$PRIMARY_PORT`; với Docker là `postgres-primary:5432`.

Kiểm tra đúng DB vừa nạp (script `verify-data.sh` cũ dùng `POSTGRES_DB` trong `.env`):

```bash
docker compose exec -T postgres-primary psql -X -v ON_ERROR_STOP=1 \
  -U postgres -d ecommerce_go < sql/verify/data-quality.sql
```

## Các chế độ và cấu hình

| Tùy chọn | Ý nghĩa |
| --- | --- |
| `small`, `default`, `5m`, `custom` | Cùng số lượng cấu hình chính với script Python; mặc định `default` |
| `--dry-run` | Sinh + mã hóa dữ liệu, hoàn toàn không kết nối DB |
| `--workers N` / `GO_WORKERS` | Số worker CPU, mặc định tối đa 4 trên host, 4 trong Compose |
| `--batch-size N` / `BATCH_SIZE` | Số user/product/order/review mỗi batch; `5m` mặc định 50.000 nếu env không đặt |
| `--bulk-load` | Chỉ dành cho DB mới chuyên dùng để nạp: tạm bỏ index phụ/UNIQUE/FK, tạo lại và validate sau COPY; giữ PK/CHECK |
| `--analyze` | Cập nhật planner statistics sau khi hoàn tất; mặc định không chạy VACUUM/ANALYZE toàn bộ |
| `--restore-schema` | Chỉ khôi phục index/FK đã ghi lại của Go, không sinh/xóa bản ghi |
| `SEED`, `DATA_NOW` / `--data-now` | Giữ cả hai để tái tạo dữ liệu ổn định |
| `NUM_*` | Chỉ áp dụng cho profile `custom` |
| `HEAVY_USER_SHARE`, `HEAVY_USER_ORDER_SHARE` | Mặc định 20% user được chọn cho 70% lượt đặt hàng |
| `AUTO_GENERATE=false` | Bỏ qua nạp data; vẫn cho phép dry-run và phục hồi schema |
| `RESET_DATA=true` | Báo lỗi trước kết nối DB; bản Go không hỗ trợ reset |

Profile phải đứng trước các flag. `--local` của shell wrapper phải đứng đầu.
Wrapper local đọc `.env` theo quy ước các script hiện có; chạy binary trực tiếp
chỉ đọc biến môi trường. `FAKER_LOCALE` không áp dụng: Go dùng danh sách tên và
vốn từ tham chiếu đã nhúng, không phụ thuộc Python/Faker lúc chạy.

## Vì sao phần sinh dữ liệu nhanh hơn

- Worker Go tạo và mã hóa nhiều batch song song; một writer ghi đúng thứ tự ID.
  Dùng [pgx COPY streaming](https://github.com/jackc/pgx/blob/master/pgconn/pgconn.go)
  với buffer text cho cả batch, tránh gọi driver/chuyển object Python từng dòng.
- Tái tạo địa chỉ mặc định từ `seed + user ID`, nên không SELECT địa chỉ lại khi
  sinh orders và không phải giữ tất cả địa chỉ trong RAM.
- Giá/tổng tiền dùng số nguyên cent. Lưu metadata liên kết trong slice gọn; giữ
  tối đa số batch bằng số worker, không giữ toàn bộ COPY payload.
- User timestamps dùng quantile đã có thứ tự; product launch trước lịch sử orders
  nên không cần UPDATE hàng triệu products sau khi nạp. Orders/reviews vẫn được
  sắp theo thời gian cho các bài lab về correlation.
- Với `--bulk-load`, index được tạo một lần bằng sort và FK được validate cuối
  cùng. Nếu giữ mọi index/FK, PostgreSQL có thể trở thành nút thắt dù CPU Go nhanh.

Bộ nhớ vẫn tăng theo users/products/orders/reviews để giữ slice và khử trùng
review; không phải O(1). Giảm `--batch-size`/`--workers` khi RAM hạn chế.

## Độ tương thích dữ liệu

Giữ schema, 50 categories, 5 warehouses, JSONB theo ngành hàng, phân phối lệch,
quan hệ và 17 kiểm tra chất lượng của dự án. `reference.json` là snapshot vốn từ
trong `data-generator/generators/reference.py`; không tự đồng bộ khi Python đổi.

Dữ liệu không giống từng byte với Python. Các khác biệt có chủ ý:

- `NUM_ORDER_ITEMS` là số chính xác, chia đều số dòng vào orders; Python dùng
  Poisson và giới hạn 10 dòng/đơn nên số thực tế chỉ xấp xỉ cấu hình.
- Reviews được khử trùng và bổ sung tới đúng target; ~75% verified khi có đủ cặp
  user/product đã mua trong đơn COMPLETED. Profile quá nhỏ có thể đạt tỷ lệ thấp hơn.
- Ngày tạo product nằm trong năm trước lịch sử orders; vốn tên và một số thuộc
  tính/phân phối được đơn giản hóa. Không dùng kết quả này để đối chiếu chính xác
  query plan, giá trị ID hoặc tỷ lệ phần trăm đã đo trên dataset Python.
- Cùng seed, DATA_NOW, số lượng và cấu hình phân phối → cùng payload Go, kể cả khi
  đổi worker/batch size. `--analyze` không cập nhật visibility map như VACUUM;
  bài lab Index Only Scan cần chạy VACUUM trên DB mới khi phù hợp.

## An toàn khi dừng/lỗi

Mỗi batch liên quan là một transaction: users+addresses, products+inventory,
orders+items+payments. Lỗi rollback batch hiện tại, giữ nguyên các batch đã commit.
ID explicit được đặt chỗ trước qua identity sequence; không set sequence lùi sau
khi nạp. Các generator Go được tuần tự hóa bằng advisory lock; lock này không
ngăn generator Python hoặc ứng dụng khác, nên không chạy chúng đồng thời trên DB đích.

Trong bulk mode, `data_generator_runs.deferred_ddl` lưu định nghĩa **trước** khi
bỏ index/FK. Khi thành công, toàn bộ định nghĩa được tạo lại và FK được validate.
Nếu bị kill/mất kết nối, phục hồi bằng:

```bash
DB_NAME=ecommerce_go ./scripts/generate-data-go.sh --restore-schema
```

Chạy phục hồi nhiều lần vẫn an toàn. Nó đánh dấu run bị gián đoạn là FAILED và giữ
partial data, không resume sinh dữ liệu. Không chạy script Python reset để phục hồi:
Python có luồng tự truncate khi nhận ra lần nạp dở. Dùng DB mới nếu cần chạy lại đầy đủ.

## Kiểm thử và số đo

```bash
cd data-generator-go
go test -race ./...
go vet ./...
go test -run '^$' -bench BenchmarkGenerateAndEncode -benchmem
cd ..
./scripts/test-go-generator.sh
```

Integration test tự tạo PostgreSQL 16 riêng trên tmpfs, tắt mạng, không gắn volume
cluster hiện tại; chỉ xóa container tạm của chính nó khi xong. Test cả normal/bulk,
17 kiểm tra SQL, so sánh đầy đủ schema, từ chối DB có data mà giữ nguyên checksum
tất cả bảng/sequence, identity allocation và phục hồi schema idempotent.

Đo ngày 01/10/2026 trên Apple M3; PostgreSQL 16 Docker tạm dùng tmpfs, không replica:

| Phép đo | Kết quả |
| --- | --- |
| Go `5m --dry-run`, 4 workers, batch 50.000 | 48.128.157 dòng, 7.417,6 MiB COPY text, **30,81 giây** (~1,56 triệu dòng/s) |
| Go `small`, giữ index/FK | ~327 nghìn dòng, **5,24 giây** |
| Go `small --bulk-load --analyze` | ~327 nghìn dòng, **3,01 giây** |
| Python hiện tại, cấu hình `small` | ~327 nghìn dòng, **4,35 giây**, gồm rebuild index/FK và VACUUM ANALYZE |

Đây là số đo một lần, dữ liệu không trùng byte và bước hoàn tất khác nhau.

Lần chạy thực tế vào DB chính `ecommerce` đã trống, ngày 01/10/2026, với primary +
streaming replica của dự án: `5m --bulk-load --analyze --batch-size 50000`, 4 workers,
**48.128.157 dòng trong 615,18 giây (~10 phút 15 giây)**. Thời gian này gồm COPY,
tạo lại 38 index/constraint và ANALYZE; không gồm các báo cáo kiểm tra chạy sau đó.
Không suy ra thời gian nạp DB từ con số dry-run; tăng worker chỉ giúp phần CPU,
không tăng tốc đĩa.
