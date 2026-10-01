# PostgreSQL Lab — Primary / Replica + E-commerce dataset

Môi trường thực hành PostgreSQL chạy 100% bằng Docker Compose:

- **PostgreSQL 16 Primary** (`localhost:5432`) — đọc + ghi
- **PostgreSQL 16 Replica** (`localhost:5433`) — hot standby, chỉ đọc, **Streaming Replication thật** (WAL + replication slot, bootstrap tự động bằng `pg_basebackup`)
- **Python data generator** (Faker + `COPY`) — nạp ~3.2 triệu dòng dữ liệu e-commerce có phân phối lệch như thực tế
- **Tài liệu + bài lab**: 60 bài tập SQL (có lời giải), transaction/isolation, MVCC, lock, index, query optimization, replication internals, backup/restore

```mermaid
flowchart LR
    DBeaver["DBeaver / psql"] -->|"read + write :5432"| P[("PRIMARY<br/>pglab-primary")]
    Gen["data-generator<br/>(Python, COPY)"] -->|"bulk load"| P
    P -->|"WAL streaming<br/>slot replica_1_slot"| R[("REPLICA<br/>pglab-replica<br/>hot_standby")]
    DBeaver -->|"read-only :5433"| R
```

Chi tiết kiến trúc: [docs/architecture.md](docs/architecture.md).

---

## 1. Yêu cầu

| | Tối thiểu |
| --- | --- |
| Docker | Docker Engine 24+ / Docker Desktop / OrbStack, Compose v2 (`docker compose`) |
| RAM cho Docker | 4 GB |
| Ổ đĩa | ~3 GB (2 × ~800 MB data + WAL + image) |
| Cổng trống | `5432`, `5433` (đổi được trong `.env`) |

Không cần cài PostgreSQL trên máy: mọi script dùng `psql` bên trong container.

## 2. Khởi động

```bash
cp .env.example .env          # tuỳ chọn - mọi biến đều có giá trị mặc định
docker compose up -d --build
```

Điều gì xảy ra khi chạy lệnh này:

1. `postgres-primary` khởi tạo cluster, chạy các script trong [postgres/primary/init/](postgres/primary/init/) (replication user + slot → extensions → schema → indexes), rồi báo `healthy`.
2. `postgres-replica` chờ primary healthy → `pg_basebackup` sao chép toàn bộ data directory → khởi động ở chế độ standby và bắt đầu stream WAL.
3. `data-generator` chờ primary healthy → sinh dữ liệu bằng `COPY` (~1.5 phút với cấu hình mặc định) → `VACUUM ANALYZE` → thoát với exit code 0. Dữ liệu tự chảy sang replica qua replication.

### Kiểm tra container

```bash
docker compose ps
```

```text
NAME                   SERVICE            STATUS
pglab-data-generator   data-generator     Exited (0)          # job chạy một lần, Exited (0) là đúng
pglab-primary          postgres-primary   Up (healthy)        127.0.0.1:5432->5432/tcp
pglab-replica          postgres-replica   Up (healthy)        127.0.0.1:5433->5432/tcp
```

### Xem log

```bash
docker compose logs -f                      # tất cả
docker compose logs -f data-generator       # tiến độ sinh dữ liệu
docker compose logs -f postgres-replica     # pg_basebackup + streaming
```

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

| | Primary | Replica |
| --- | --- | --- |
| Host | `localhost` | `localhost` |
| Port | `5432` | `5433` |
| Database | `ecommerce` | `ecommerce` |
| Username | `postgres` | `postgres` |
| Password | `postgres` | `postgres` |
| Quyền | đọc + ghi | **chỉ đọc** |

**DBeaver**: *Database → New Database Connection → PostgreSQL*, điền bảng trên (tạo 2 connection). Gợi ý:

- Đặt tên `pglab PRIMARY` / `pglab REPLICA`, và ở tab *General* chọn *Connection type = Production* cho replica để DBeaver tô màu, dễ phân biệt.
- Transaction lab cần mở **2 connection tới cùng primary** (Session A, Session B) và tắt *Auto-commit* khi đề bài yêu cầu `BEGIN` thủ công (hoặc dùng *Smart commit mode* off).

**psql trong container** (không cần cài gì):

```bash
./scripts/psql.sh                 # primary
./scripts/psql.sh replica         # replica
./scripts/psql.sh primary -c "SELECT count(*) FROM orders"
```

**psql trên máy host** (nếu có cài): `psql "postgresql://postgres:postgres@localhost:5432/ecommerce"`

**Python**:

```python
import psycopg
with psycopg.connect("host=localhost port=5433 dbname=ecommerce user=postgres password=postgres") as conn:
    print(conn.execute("SELECT pg_is_in_recovery()").fetchone())   # (True,) -> replica
```

## 4. Dữ liệu

| Bảng | Số dòng (mặc định) | Ghi chú |
| --- | ---: | --- |
| `categories` | 50 | cây 2 cấp: 10 danh mục cha × 4 danh mục con |
| `users` | 100,000 | `id` tăng theo `created_at` (đăng ký), JSONB `metadata` |
| `addresses` | ~160,000 | 1–3 địa chỉ/user, đúng 1 địa chỉ mặc định |
| `warehouses` | 5 | |
| `products` | 100,000 | giá theo từng danh mục, JSONB `attributes` khác nhau theo ngành hàng, `tags text[]` |
| `inventory` | 100,000 | tồn kho theo (product, warehouse) |
| `orders` | 500,000 | 3 năm lịch sử, `id` tăng theo thời gian |
| `order_items` | ~1,500,000 | tiền tính bằng cent → CHECK `total = qty × price − discount` luôn đúng |
| `payments` | ~513,000 | ~3% đơn có một lần thanh toán FAILED trước đó |
| `reviews` | 300,000 | ~75% là verified purchase (gắn với order COMPLETED thật) |

**Phân phối không đồng đều (cố ý)** — để query planner có cái mà "suy nghĩ":

| Đặc điểm | Giá trị |
| --- | --- |
| 20% user tạo ~70% đơn hàng | `HEAVY_USER_SHARE`, `HEAVY_USER_ORDER_SHARE` |
| Độ phổ biến sản phẩm theo Zipf | top 1% sản phẩm ≈ 50% lượt bán; ~10% sản phẩm chưa từng bán |
| Order status | COMPLETED 60%, SHIPPED 13%, CANCELLED 10%, PROCESSING 7%, PENDING 5%, CONFIRMED 5% |
| Đơn "đang mở" là đơn mới | PENDING ≤ 10 ngày, CONFIRMED ≤ 20, PROCESSING ≤ 45, SHIPPED ≤ 90 ngày |
| Mùa cao điểm | ~10% đơn rơi vào Black Friday → Giáng sinh; giờ cao điểm buổi tối |
| Thành phố | New York, Los Angeles… chiếm phần lớn, hàng nghìn thị trấn chỉ vài địa chỉ; 15% quốc tế (VN, GB, CA, JP…) |
| Rating | hình chữ J (nhiều 5★, có "gò" ở 1★), phụ thuộc "chất lượng ẩn" của sản phẩm |

### Sinh lại / đổi kích thước dữ liệu

Generator có tính **idempotent**: nếu đã có một lần chạy `COMPLETED` (bảng `data_generator_runs`) thì lần `up` sau sẽ bỏ qua.

```bash
# chạy generator thủ công (bỏ qua nếu đã có dữ liệu)
docker compose run --rm data-generator

# xoá sạch và sinh lại
docker compose run --rm -e RESET_DATA=true data-generator

# dataset nhỏ để thử nhanh
docker compose run --rm -e RESET_DATA=true -e NUM_USERS=10000 -e NUM_PRODUCTS=10000 \
  -e NUM_ORDERS=50000 -e NUM_ORDER_ITEMS=150000 -e NUM_INVENTORY=10000 -e NUM_REVIEWS=30000 data-generator
```

Hoặc sửa trong `.env` (`NUM_USERS`, `NUM_PRODUCTS`, `NUM_ORDERS`, `NUM_ORDER_ITEMS`, `NUM_INVENTORY`, `NUM_REVIEWS`, `BATCH_SIZE`, `SEED`, …). Cùng `SEED` → cùng dữ liệu.

## 5. Scripts

| Script | Tác dụng |
| --- | --- |
| [scripts/check-replication.sh](scripts/check-replication.sh) | Báo cáo đầy đủ: `pg_stat_replication`, slot, LSN, lag, `pg_is_in_recovery()`, so sánh số dòng. Exit code ≠ 0 nếu có vấn đề |
| [scripts/replication-test.sh](scripts/replication-test.sh) | INSERT trên primary → poll replica → đo thời gian → chứng minh replica từ chối ghi |
| [scripts/backup.sh](scripts/backup.sh) | `pg_dump` ra `backups/` (`--from-replica`, `--plain`, `--db`) |
| [scripts/restore.sh](scripts/restore.sh) | `pg_restore` song song vào DB mới (mặc định `ecommerce_restore`) |
| [scripts/rebuild-replica.sh](scripts/rebuild-replica.sh) | Xoá replica và clone lại từ primary (sau bài failover) |
| [scripts/psql.sh](scripts/psql.sh) | `psql` tương tác vào primary / replica |

SQL giám sát dùng sẵn trong DBeaver: [sql/monitoring/](sql/monitoring/) — `replication.sql`, `activity.sql`, `locks.sql`, `size.sql`, `performance.sql`.

## 6. Lộ trình học

| # | Tài liệu | Nội dung |
| --- | --- | --- |
| 1 | [docs/architecture.md](docs/architecture.md) | Kiến trúc, process, volume, ER diagram |
| 2 | [docs/sql-exercises.md](docs/sql-exercises.md) → [docs/sql-solutions.md](docs/sql-solutions.md) | 60 bài, 10 level: SQL cơ bản → JOIN → aggregation → CTE → window → index → optimization → transaction → locking → internals |
| 3 | [docs/index-lab.md](docs/index-lab.md) | B-tree, composite, partial, expression, covering, GIN/JSONB, trigram, BRIN, index thừa, FK không có index |
| 4 | [docs/query-optimization-lab.md](docs/query-optimization-lab.md) | Đọc EXPLAIN, estimate vs actual, các loại scan/join, statistics, work_mem, phân trang |
| 5 | [docs/transaction-lab.md](docs/transaction-lab.md) | Session A/B: lost update, dirty/non-repeatable/phantom read, row lock, deadlock, isolation level |
| 6 | [docs/mvcc-lab.md](docs/mvcc-lab.md) | `xmin`/`xmax`/`ctid`, pageinspect, HOT update, dead tuple, VACUUM |
| 7 | [docs/monitoring.md](docs/monitoring.md) | `pg_stat_activity`, `pg_locks`, blocking, kích thước, `pg_stat_statements` |
| 8 | [docs/replication.md](docs/replication.md) | Luồng INSERT → WAL → replica chi tiết, metric, read/write, sync replication, failover |
| 9 | [docs/backup-restore.md](docs/backup-restore.md) | `pg_dump`/`pg_restore`, logical vs physical, PITR |

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

| Triệu chứng | Nguyên nhân / cách xử lý |
| --- | --- |
| `Bind for 127.0.0.1:5432 failed: port is already allocated` | Có PostgreSQL/container khác đang dùng cổng. Tìm bằng `lsof -iTCP:5432 -sTCP:LISTEN` hoặc `docker ps`, hoặc đổi `PRIMARY_PORT`/`REPLICA_PORT` trong `.env` |
| Replica `unhealthy` / `check-replication.sh` báo FAIL | `docker compose logs postgres-replica`. Nếu replica đã bị promote hoặc slot bị `lost`: `./scripts/rebuild-replica.sh` |
| Generator in `Data already generated ... skipping` | Bình thường. Muốn sinh lại: `RESET_DATA=true` (xem mục 4) |
| Generator bị dừng giữa chừng | Lần chạy sau tự phát hiện run chưa hoàn tất, truncate và sinh lại |
| Muốn primary/replica nghe trên mọi interface | `BIND_ADDRESS=0.0.0.0` trong `.env` (chỉ nên làm trong mạng tin cậy — mật khẩu lab rất yếu) |
| Đổi `postgresql.conf` | Sửa file trong `postgres/*/`, rồi `docker compose up -d --build` (tham số cần restart) hoặc `SELECT pg_reload_conf()` |
| Đổi schema trong `init/*.sql` | Init script chỉ chạy khi volume trống → `docker compose down -v && docker compose up -d --build` |

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
