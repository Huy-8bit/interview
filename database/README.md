# PostgreSQL Lab — Primary / Replica + E-commerce dataset

Môi trường thực hành PostgreSQL chạy 100% bằng Docker Compose:

- **PostgreSQL 16 Primary** (`localhost:55435`) — đọc + ghi
- **PostgreSQL 16 Replicas** (`localhost:55436`, `localhost:55437`) — hai hot standby chỉ đọc, **Streaming Replication thật** (WAL + replication slot riêng, bootstrap tự động bằng `pg_basebackup`)
- **LockLens** (`http://localhost:8080`) — giao diện giám sát PostgreSQL, API và store riêng; backend kết nối cùng Docker network với cả ba node
- **Synthetic workload** — mặc định 80 kết nối đồng thời: 40 CRUD trên Primary, 20 SELECT trên mỗi Replica
- **Python data generator** (Faker + `COPY`) — nạp ~3.2 triệu dòng dữ liệu e-commerce có phân phối lệch như thực tế
- **Tài liệu + bài lab**: 60 bài tập SQL (có lời giải), transaction/isolation, MVCC, lock, index, query optimization, replication internals, backup/restore

```mermaid
flowchart LR
    DBeaver["DBeaver / psql"] -->|"read + write :55435"| P[("PRIMARY<br/>pglab-primary")]
    Gen["data-generator<br/>(Python, COPY)"] -->|"bulk load"| P
    P -->|"WAL streaming<br/>slot replica_1_slot"| R1[("REPLICA 1<br/>pglab-replica<br/>hot_standby")]
    P -->|"WAL streaming<br/>slot replica_2_slot"| R2[("REPLICA 2<br/>pglab-replica-2<br/>hot_standby")]
    DBeaver -->|"read-only :55436"| R1
    DBeaver -->|"read-only :55437"| R2
```

Chi tiết kiến trúc: [docs/architecture.md](docs/architecture.md).

### Lệnh nhanh

| Việc                                                     | Lệnh                                                                  |
| --------------------------------------------------------- | ---------------------------------------------------------------------- |
| Khởi động (database + LockLens + sinh dữ liệu)       | `docker compose up -d --build`                                       |
| Trạng thái / health                                     | `docker compose ps`                                                  |
| Log                                                       | `docker compose logs -f`                                             |
| Kiểm tra replication                                     | `./scripts/check-replication.sh`                                     |
| Test INSERT primary → SELECT replica                     | `./scripts/replication-test.sh`                                      |
| psql vào primary / replica                               | `./scripts/psql.sh` / `./scripts/psql.sh replica` / `./scripts/psql.sh replica-2` |
| Backup / restore                                          | `./scripts/backup.sh` / `./scripts/restore.sh backups/<file>.dump` |
| Dừng (giữ dữ liệu)                                    | `docker compose down`                                                |
| Xoá sạch dữ liệu (chỉ khi thật sự muốn)           | `docker compose down -v`                                             |

Kết nối: **Primary `localhost:55435`**, **Replica 1 `localhost:55436`**, **Replica 2 `localhost:55437`**, database `ecommerce`, user/password `postgres` / `postgres`. LockLens tại `http://localhost:8080`.

---

## 1. Yêu cầu

|                | Tối thiểu                                                                    |
| -------------- | ------------------------------------------------------------------------------ |
| Docker         | Docker Engine 24+ / Docker Desktop / OrbStack, Compose v2 (`docker compose`) |
| RAM cho Docker | 4 GB                                                                           |
| Ổ đĩa       | ~4 GB (3 data directories + WAL + image)                                      |
| Cổng trống   | `55435`, `55436`, `55437`, `8080` (đổi được trong `.env`)                   |

Không cần cài PostgreSQL trên máy: mọi script dùng `psql` bên trong container.
Ba container PostgreSQL mặc định có giới hạn `/dev/shm` là 2 GB mỗi container để hỗ trợ `VACUUM`/index song song trên bảng lớn. Có thể đổi bằng `POSTGRES_SHM_SIZE` trong `.env`; đây là giới hạn dung lượng, không phải RAM cấp phát trước. Các profile dữ liệu lớn cần Docker VM có đủ RAM và ổ đĩa riêng.

## 2. Khởi động

```bash
cp .env.example .env          # chỉ chạy lần đầu nếu chưa có .env
# Sửa các giá trị LOCKLENS_* trong .env; dùng secrets ngẫu nhiên, ví dụ:
# openssl rand -hex 32       # LOCKLENS_STORE_PASSWORD và LOCKLENS_ADMIN_PASSWORD
# openssl rand -base64 32    # LOCKLENS_MASTER_KEY (lưu lại để giữ các DSN đã lưu)
docker compose up -d --build
```

Nếu đã có `database/.env`, giữ nguyên các cấu hình database hiện tại và chỉ thêm/cập nhật các biến `LOCKLENS_*` từ `.env.example`; không ghi đè toàn bộ file.

Điều gì xảy ra khi chạy lệnh này:

1. `postgres-primary` khởi tạo cluster, chạy các script trong [postgres/primary/init/](postgres/primary/init/) (replication user + slot → extensions → schema → indexes), rồi báo `healthy`.
2. `postgres-replica` và `postgres-replica-2` chờ primary healthy → mỗi replica dùng replication slot riêng và `pg_basebackup` sao chép data directory → khởi động ở chế độ standby, bắt đầu stream WAL.
3. `data-generator` chờ primary healthy → sinh dữ liệu bằng `COPY` (~1.5 phút với cấu hình mặc định) → `VACUUM ANALYZE` → thoát với exit code 0. Dữ liệu tự chảy sang hai replica qua replication.
4. `workload-init` tạo bảng workload riêng; ba `workload-*` service mở tổng cộng 80 kết nối pgbench liên tục: Primary chạy INSERT/SELECT/UPDATE/DELETE, hai Replica chỉ chạy SELECT.
5. `locklens-store`, `locklens-backend` và `frontend` khởi động; frontend phục vụ UI, backend giám sát PostgreSQL, store giữ lịch sử và DSN được mã hoá.

Đăng nhập LockLens bằng `LOCKLENS_ADMIN_USER` và `LOCKLENS_ADMIN_PASSWORD` đã đặt trong `.env`. Trong **Settings → Add instance**, thêm các connection sau (backend dùng DNS nội bộ Docker):

```text
Primary:   postgresql://postgres:postgres@postgres-primary:5432/ecommerce?sslmode=disable
Replica 1: postgresql://postgres:postgres@postgres-replica:5432/ecommerce?sslmode=disable
Replica 2: postgresql://postgres:postgres@postgres-replica-2:5432/ecommerce?sslmode=disable
```

Thêm **Primary trước**, rồi thêm hai Replica để LockLens có thể tái sử dụng role đã tạo. Chọn cùng một Environment, ví dụ `lab-postgres` (không dùng dấu cách). Các DSN trên dùng tài khoản lab `postgres`; LockLens sẽ yêu cầu xác nhận trước khi tạo role giám sát/đọc riêng.

### Kiểm tra container

```bash
docker compose ps
```

```text
NAME                   SERVICE            STATUS
pglab-data-generator   data-generator     Exited (0)          # job chạy một lần, Exited (0) là đúng
pglab-primary          postgres-primary   Up (healthy)        127.0.0.1:55435->5432/tcp
pglab-replica          postgres-replica   Up (healthy)        127.0.0.1:55436->5432/tcp
pglab-replica-2        postgres-replica-2 Up (healthy)        127.0.0.1:55437->5432/tcp
pglab-locklens-frontend frontend          Up (healthy)        127.0.0.1:8080->8080/tcp
```

### Xem log

```bash
docker compose logs -f                      # tất cả
docker compose logs -f data-generator       # tiến độ sinh dữ liệu
docker compose logs -f postgres-replica     # pg_basebackup + streaming
docker compose logs -f postgres-replica-2   # replica thứ hai
docker compose logs -f locklens-backend    # API / collectors
docker compose logs -f workload-primary workload-replica-1 workload-replica-2
```

### Tải giả lập backend

Tải bật mặc định cùng `docker compose up -d`: 40 kết nối CRUD vào Primary và 20 kết nối đọc vào mỗi Replica (80 client kết nối liên tục). Có thể đổi số client bằng `WORKLOAD_PRIMARY_CLIENTS`, `WORKLOAD_REPLICA_1_CLIENTS`, `WORKLOAD_REPLICA_2_CLIENTS` trong `.env`, rồi recreate ba workload service. Chúng dùng `application_name` riêng để lọc trên LockLens và `pg_stat_activity`.

```bash
docker compose ps workload-primary workload-replica-1 workload-replica-2
docker compose stop workload-primary workload-replica-1 workload-replica-2  # dừng tải, giữ DB
docker compose start workload-primary workload-replica-1 workload-replica-2 # chạy tải lại
```

Xem số kết nối và câu lệnh trên từng node:

```bash
docker compose exec postgres-primary psql -U postgres -d ecommerce -c \
  "SELECT application_name, state, count(*) FROM pg_stat_activity WHERE application_name LIKE 'backend-simulator-%' GROUP BY 1,2 ORDER BY 1,2;"
docker compose exec postgres-primary psql -U postgres -d ecommerce -c \
  "SELECT query, calls FROM pg_stat_statements WHERE query ILIKE '%backend_workload_items%' ORDER BY calls DESC LIMIT 10;"
```

Replica chỉ nhận SELECT vì PostgreSQL hot standby không cho ghi; thao tác ghi trên Primary được stream qua WAL. Dừng riêng simulator Go cũ nếu còn chạy: `docker stop pglab-backend-simulator`.

Log generator mẫu:

```text
Generating users...
  Users: 10000 / 100000   (   1.6s, 6,250 rows/s)
  Users: 20000 / 100000   (   3.1s, 6,450 rows/s)
...
Generating orders...
  Orders: 10000 / 500000   (   1.0s, 9,900 rows/s)
...
Data generation completed in 1.4 min  (database size: 798 MB)
```

### Kiểm tra replication

```bash
./scripts/check-replication.sh     # trạng thái primary, replica, slot, lag, so sánh số dòng
./scripts/replication-test.sh      # INSERT trên primary -> đợi thấy trên replica -> thử ghi trên replica (phải lỗi)
```

## 3. Kết nối

|          | Primary       | Replica 1           | Replica 2           |
| -------- | ------------- | ------------------- | ------------------- |
| Host     | `localhost`   | `localhost`         | `localhost`         |
| Port     | `55435`       | `55436`             | `55437`             |
| Database | `ecommerce`   | `ecommerce`         | `ecommerce`         |
| Username | `postgres`    | `postgres`          | `postgres`          |
| Password | `postgres`    | `postgres`          | `postgres`          |
| Quyền    | đọc + ghi     | **chỉ đọc**         | **chỉ đọc**         |

**DBeaver**: *Database → New Database Connection → PostgreSQL*, điền bảng trên (tạo 3 connection). Gợi ý:

- Host luôn là `localhost` (hoặc `127.0.0.1`). **Không** dùng `postgres-primary` / `postgres-replica` — đó là hostname bên trong Docker network, máy host không phân giải được.
- Lần đầu DBeaver sẽ đề nghị tải driver PostgreSQL — chọn *Download*.
- Đặt tên `pglab PRIMARY`, `pglab REPLICA 1`, `pglab REPLICA 2`; ở tab *General* chọn *Connection type = Production* cho hai replica để DBeaver tô màu, dễ phân biệt.
- Transaction lab cần mở **2 connection tới cùng primary** (Session A, Session B) và tắt *Auto-commit* khi đề bài yêu cầu `BEGIN` thủ công (hoặc dùng *Smart commit mode* off).

**Connection string Replica 2** (để thêm vào DBeaver/DB client):

```text
postgresql://postgres:postgres@localhost:55437/ecommerce?sslmode=disable
```

Nếu client chạy **trong một Docker container khác** (ví dụ LockLens), dùng host gateway thay cho `localhost`:

```text
postgresql://postgres:postgres@host.docker.internal:55437/ecommerce?sslmode=disable
```

Trong LockLens chạy cùng Compose, dùng connection string nội bộ `postgres-replica-2:5432` như phần khởi động ở trên; `localhost` hoặc `host.docker.internal` không cần thiết.

**psql trong container** (không cần cài gì):

```bash
./scripts/psql.sh                 # primary
./scripts/psql.sh replica         # replica
./scripts/psql.sh replica-2       # replica thứ hai
./scripts/psql.sh primary -c "SELECT count(*) FROM orders"
```

**psql trên máy host** (nếu có cài): `psql "postgresql://postgres:postgres@localhost:55435/ecommerce"`

**Python**:

```python
import psycopg
with psycopg.connect("host=localhost port=55436 dbname=ecommerce user=postgres password=postgres") as conn:
    print(conn.execute("SELECT pg_is_in_recovery()").fetchone())   # (True,) -> replica
```

## 4. Dữ liệu

| Bảng           | Số dòng (mặc định) | Ghi chú                                                                                     |
| --------------- | ----------------------: | -------------------------------------------------------------------------------------------- |
| `categories`  |                      50 | cây 2 cấp: 10 danh mục cha × 4 danh mục con                                             |
| `users`       |                 100,000 | `id` tăng theo `created_at` (đăng ký), JSONB `metadata`                            |
| `addresses`   |                ~160,000 | 1–3 địa chỉ/user, đúng 1 địa chỉ mặc định                                        |
| `warehouses`  |                       5 |                                                                                              |
| `products`    |                 100,000 | giá theo từng danh mục, JSONB`attributes` khác nhau theo ngành hàng, `tags text[]` |
| `inventory`   |                 100,000 | tồn kho theo (product, warehouse)                                                           |
| `orders`      |                 500,000 | 3 năm lịch sử,`id` tăng theo thời gian                                                |
| `order_items` |              ~1,500,000 | tiền tính bằng cent → CHECK`total = qty × price − discount` luôn đúng             |
| `payments`    |                ~513,000 | ~3% đơn có một lần thanh toán FAILED trước đó                                      |
| `reviews`     |                 300,000 | ~75% là verified purchase (gắn với order COMPLETED thật)                                 |

**Phân phối không đồng đều (cố ý)** — để query planner có cái mà "suy nghĩ":

| Đặc điểm                         | Giá trị                                                                                                                 |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| 20% user tạo ~70% đơn hàng       | `HEAVY_USER_SHARE`, `HEAVY_USER_ORDER_SHARE`                                                                          |
| Độ phổ biến sản phẩm theo Zipf | top 1% sản phẩm ≈ 50% lượt bán; ~10% sản phẩm chưa từng bán                                                    |
| Order status                         | COMPLETED 60%, SHIPPED 13%, CANCELLED 10%, PROCESSING 7%, PENDING 5%, CONFIRMED 5%                                        |
| Đơn "đang mở" là đơn mới     | PENDING ≤ 10 ngày, CONFIRMED ≤ 20, PROCESSING ≤ 45, SHIPPED ≤ 90 ngày                                               |
| Mùa cao điểm                      | ~10% đơn rơi vào Black Friday → Giáng sinh; giờ cao điểm buổi tối                                              |
| Thành phố                          | New York, Los Angeles… chiếm phần lớn, hàng nghìn thị trấn chỉ vài địa chỉ; 15% quốc tế (VN, GB, CA, JP…) |
| Rating                               | hình chữ J (nhiều 5★, có "gò" ở 1★), phụ thuộc "chất lượng ẩn" của sản phẩm                              |

### Sinh lại / đổi kích thước dữ liệu

**Bản Go tạo data nhanh:** xem [data-generator-go/README.md](data-generator-go/README.md).
Chạy `./scripts/generate-data-go.sh 5m --dry-run` để đo tốc độ sinh dữ liệu mà không
kết nối DB. Bản Go từ chối DB có dữ liệu, không hỗ trợ reset/xóa; nạp DB mới bằng
`DB_NAME=ecommerce ./scripts/generate-data-go.sh 5m --bulk-load --analyze --batch-size 50000`
khi DB chính đã trống và identity đã reset. Nếu muốn dùng DB riêng, cần tạo database
và schema trước khi đặt `DB_NAME` tương ứng. Script Python dưới đây vẫn có hành vi xóa dữ liệu cũ.

```bash
./scripts/generate-data.sh small      # ~10% mặc định, < 1 phút
./scripts/generate-data.sh default    # ~3.3 triệu dòng, ~1.5 phút (giống lần `up` đầu tiên)
./scripts/generate-data.sh 5m         # ~5 triệu dòng mỗi bảng chính, ~20 phút, ~13 GB mỗi node
./scripts/generate-data.sh custom     # lấy NUM_* / BATCH_SIZE từ .env
#   thêm -y để không hỏi xác nhận, --no-verify để bỏ bước kiểm tra
```

Script **xoá dữ liệu hiện tại** (TRUNCATE), sinh lại, kiểm tra replication, rồi chạy `./scripts/verify-data.sh`. Replica tự nhận dữ liệu mới qua streaming replication.

Profile `5m` (đo trên Docker Desktop 8 CPU / 8 GB RAM; ở quy mô 1/5 mất 3.6 phút, 2.7 GB):

| Bảng           |   Số dòng | Quan hệ                                                                                                             |
| --------------- | ----------: | -------------------------------------------------------------------------------------------------------------------- |
| `users`       |   5,000,000 | 20% user tạo ~65% số đơn                                                                                         |
| `addresses`   |  ~8,000,000 | 1–3 địa chỉ/user, đúng 1 địa chỉ mặc định                                                                |
| `products`    |   5,000,000 | thuộc 1 trong 40 danh mục con; độ phổ biến theo Zipf                                                           |
| `inventory`   |   5,000,000 | `products.stock_quantity` = tổng tồn kho                                                                         |
| `orders`      |   5,000,000 | đặt sau khi user đăng ký;`shipping_address` = địa chỉ mặc định của user                                |
| `order_items` | ~10,000,000 | trung bình 2 dòng/đơn;`orders.subtotal` = tổng các dòng                                                     |
| `payments`    |  ~5,150,000 | `amount` = `orders.total_amount`; trạng thái khớp trạng thái đơn; ~3% có lần thanh toán FAILED trước |
| `reviews`     |   5,000,000 | ~75% verified: trỏ tới đúng đơn COMPLETED của user có chứa sản phẩm đó                                  |

Muốn đúng 5 triệu `order_items` (mỗi đơn 1 dòng): dùng `custom` với `NUM_ORDER_ITEMS=5000000` trong `.env`.

**Generator nạp nhanh thế nào**: `COPY` theo batch; trước khi nạp, nó tạm bỏ index phụ / UNIQUE / FOREIGN KEY và tạo lại sau khi nạp xong. Tạo index một lần bằng sort, rồi validate FK trên toàn bộ dữ liệu bằng một phép join, nhanh hơn ~20 lần so với cập nhật index từng dòng ở quy mô hàng triệu. Định nghĩa của các đối tượng bị bỏ được lưu vào `data_generator_runs.deferred_ddl` **trước khi** drop; nếu generator chết giữa chừng, lần chạy sau tự tạo lại. Bộ nhớ của generator luôn dưới ~1 GB nhờ dùng mảng gọn thay vì object Python.

**Kiểm tra dữ liệu** (mặc định chạy trên replica):

```bash
./scripts/verify-data.sh              # 17 check: FK, tổng tiền, payment khớp đơn, review gắn với đơn thật,
                                      # thứ tự thời gian (không bán sản phẩm trước khi nó tồn tại...),
                                      # phân phối, và vài query JOIN mẫu trả về dữ liệu thật
./scripts/verify-data.sh --primary
```

Chạy thủ công bằng compose (tương đương):

```bash
docker compose run --rm data-generator                    # bỏ qua nếu lần chạy gần nhất đã COMPLETED
docker compose run --rm -e RESET_DATA=true data-generator # xoá và sinh lại theo .env
```

Mọi biến nằm trong `.env` (`NUM_USERS`, `NUM_PRODUCTS`, `NUM_ORDERS`, `NUM_ORDER_ITEMS`, `NUM_INVENTORY`, `NUM_REVIEWS`, `BATCH_SIZE`, `SEED`, `DATA_NOW`, …). Cùng `SEED` + cùng `DATA_NOW` → dữ liệu giống hệt từng byte.

⚠️ Các con số trong docs (ví dụ "user 55368 có 36 đơn", kích thước index, thời gian query) được đo trên profile **default**. Ở profile `5m` plan và thời gian sẽ khác — đó cũng là một bài tập hay: so sánh plan của cùng một query ở hai quy mô.

## 5. Scripts

| Script                                                                | Tác dụng                                                                                                                                   |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| [scripts/check-replication.sh](scripts/check-replication.sh)           | Báo cáo đầy đủ:`pg_stat_replication`, slot, LSN, lag, `pg_is_in_recovery()`, so sánh số dòng. Exit code ≠ 0 nếu có vấn đề |
| [scripts/replication-test.sh](scripts/replication-test.sh)             | INSERT trên primary → poll replica → đo thời gian → chứng minh replica từ chối ghi                                                  |
| [scripts/backup.sh](scripts/backup.sh)                                 | `pg_dump` ra `backups/` (`--from-replica`, `--plain`, `--db`)                                                                      |
| [scripts/restore.sh](scripts/restore.sh)                               | `pg_restore` song song vào DB mới (mặc định `ecommerce_restore`)                                                                    |
| [scripts/rebuild-replica.sh](scripts/rebuild-replica.sh)               | Xoá replica và clone lại từ primary (sau bài failover)                                                                                  |
| [scripts/generate-data.sh](scripts/generate-data.sh)                   | Sinh lại dữ liệu theo profile`small` / `default` / `5m` / `custom`, rồi verify                                                   |
| [scripts/verify-data.sh](scripts/verify-data.sh)                       | 17 check tính toàn vẹn / quan hệ / thời gian + query JOIN mẫu ([sql/verify/data-quality.sql](sql/verify/data-quality.sql))              |
| [scripts/test-optimization-labs.sh](scripts/test-optimization-labs.sh) | Chạy toàn bộ lab tối ưu + thử thách, kiểm tra reset về baseline sau mỗi bài                                                       |
| [scripts/psql.sh](scripts/psql.sh)                                     | `psql` tương tác vào primary / replica                                                                                                 |

SQL giám sát dùng sẵn trong DBeaver: [sql/monitoring/](sql/monitoring/) — `replication.sql`, `activity.sql`, `locks.sql`, `size.sql`, `performance.sql`.

## 6. Lộ trình học

| #  | Tài liệu                                                                                     | Nội dung                                                                                                                                                                                                                                  |
| -- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1  | [docs/architecture.md](docs/architecture.md)                                                    | Kiến trúc, process, volume, ER diagram                                                                                                                                                                                                   |
| 2  | [docs/sql-exercises.md](docs/sql-exercises.md) → [docs/sql-solutions.md](docs/sql-solutions.md) | 60 bài, 10 level: SQL cơ bản → JOIN → aggregation → CTE → window → index → optimization → transaction → locking → internals                                                                                                    |
| 3  | [docs/index-lab.md](docs/index-lab.md)                                                          | B-tree, composite, partial, expression, covering, GIN/JSONB, trigram, BRIN, index thừa, FK không có index                                                                                                                               |
| 4  | [docs/query-optimization-lab.md](docs/query-optimization-lab.md)                                | Đọc EXPLAIN, estimate vs actual, các loại scan/join, statistics, work_mem, phân trang                                                                                                                                                 |
| 5  | [docs/transaction-lab.md](docs/transaction-lab.md)                                              | Session A/B: lost update, dirty/non-repeatable/phantom read,`SELECT FOR UPDATE`, blocking, READ COMMITTED / REPEATABLE READ / SERIALIZABLE, deadlock, long-running transaction (hàng đợi lock, VACUUM bị chặn), idle in transaction |
| 6  | [docs/mvcc-lab.md](docs/mvcc-lab.md)                                                            | `xmin`/`xmax`/`ctid`, pageinspect, HOT update, dead tuple, VACUUM                                                                                                                                                                    |
| 7  | [docs/monitoring.md](docs/monitoring.md)                                                        | `pg_stat_activity`, `pg_locks`, blocking tree, kích thước, `pg_stat_statements`, WAL/checkpoint, đọc đúng replication lag                                                                                                     |
| 8  | [docs/replication.md](docs/replication.md)                                                      | Luồng INSERT → WAL → replica chi tiết, metric, read/write, sync replication, failover                                                                                                                                                  |
| 9  | [docs/backup-restore.md](docs/backup-restore.md)                                                | `backup.sh`/`restore.sh`, định dạng dump, restore chọn lọc, khôi phục dữ liệu xoá nhầm, `pg_basebackup`, PITR                                                                                                             |
| 10 | [sql/optimization/](sql/optimization/)                                                          | **41 bài tối ưu query** trên dataset 5m (mỗi bài: before → EXPLAIN / ANALYZE / BUFFERS → tối ưu → after → so sánh → reset), plan quan sát thật, 15 thử thách + lời giải                                          |

## 7. Dừng / reset

```bash
docker compose stop              # dừng, giữ container + dữ liệu
docker compose down              # xoá container + network, GIỮ dữ liệu (volumes)
docker compose up -d             # chạy lại: dữ liệu còn nguyên, generator tự bỏ qua

docker compose down -v           # xoá luôn volumes -> MẤT toàn bộ dữ liệu
docker compose up -d --build     # khởi tạo lại từ đầu
```

Volumes: `postgresql-lab_postgres_primary_data`, `postgresql-lab_postgres_replica_data` (`docker volume ls | grep postgresql-lab`).

## 8. Xử lý sự cố

| Triệu chứng                                                                                  | Nguyên nhân / cách xử lý                                                                                                                                                   |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Bind for 127.0.0.1:55435 failed: port is already allocated`                                 | Có PostgreSQL/container khác đang dùng cổng. Tìm bằng`lsof -iTCP:55435 -sTCP:LISTEN` hoặc `docker ps`, hoặc đổi `PRIMARY_PORT`/`REPLICA_PORT` trong `.env` |
| `check-replication.sh` báo `replay_lag` rỗng / `since_last_replayed_commit` tăng dần | Bình thường khi không có ghi mới: lag thật là dòng`lag` (so LSN primary vs replica)                                                                                  |
| Replica`unhealthy` / `check-replication.sh` báo FAIL                                      | `docker compose logs postgres-replica`. Nếu replica đã bị promote hoặc slot bị `lost`: `./scripts/rebuild-replica.sh`                                               |
| Generator in`Data already generated ... skipping`                                            | Bình thường. Muốn sinh lại:`RESET_DATA=true` (xem mục 4)                                                                                                                |
| Generator bị dừng giữa chừng                                                               | Lần chạy sau tự phát hiện run chưa hoàn tất, truncate và sinh lại                                                                                                     |
| Muốn primary/replica nghe trên mọi interface                                                | `BIND_ADDRESS=0.0.0.0` trong `.env` (chỉ nên làm trong mạng tin cậy — mật khẩu lab rất yếu)                                                                       |
| Đổi`postgresql.conf`                                                                       | Sửa file trong`postgres/*/`, rồi `docker compose up -d --build` (tham số cần restart) hoặc `SELECT pg_reload_conf()`                                                 |
| Đổi schema trong`init/*.sql`                                                               | Init script chỉ chạy khi volume trống →`docker compose down -v && docker compose up -d --build`                                                                           |

## 9. Cấu trúc project

```text
.
├── docker-compose.yml
├── .env.example                  # mọi biến cấu hình (copy thành .env)
├── postgres/
│   ├── primary/
│   │   ├── Dockerfile
│   │   ├── postgresql.conf       # wal_level, max_wal_senders, slots, logging, pg_stat_statements...
│   │   ├── pg_hba.conf           # "host replication all samenet scram-sha-256"
│   │   └── init/
│   │       ├── 01-create-replication-user.sh   # role replicator + physical slot
│   │       ├── 02-extensions.sql               # pg_stat_statements, pg_trgm, pageinspect, pg_walinspect...
│   │       ├── 03-schema.sql                   # bảng, enum, constraint, trigger
│   │       └── 04-indexes.sql                  # index có chủ đích + danh sách index CỐ Ý thiếu
│   └── replica/
│       ├── Dockerfile
│       ├── entrypoint.sh         # chờ primary -> pg_basebackup -R -> start standby
│       ├── postgresql.conf       # hot_standby, hot_standby_feedback...
│       └── pg_hba.conf
├── data-generator/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py                   # điều phối, idempotent, VACUUM ANALYZE
│   └── generators/               # config, db (COPY), distributions, catalog, users, products, orders, reviews
├── scripts/                      # check-replication, replication-test, backup, restore, rebuild-replica, psql
├── sql/monitoring/               # truy vấn giám sát mở bằng DBeaver
├── backups/                      # output của backup.sh (git-ignored)
└── docs/
```
