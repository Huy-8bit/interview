# Kiến trúc

## 1. Tổng thể

```mermaid
flowchart TB
    subgraph HOST["Máy host (macOS / Linux / Windows)"]
        DBeaver["DBeaver / psql / app"]
        Scripts["scripts/*.sh<br/>(docker compose exec)"]
        Backups[("./backups/*.dump")]
    end

    subgraph NET["Docker network: postgresql-lab_pgnet"]
        Gen["data-generator<br/>Python 3.12 + Faker + psycopg 3<br/>(one-shot job)"]

        subgraph PRIMARY["Container pglab-primary (hostname postgres-primary)"]
            direction TB
            PM1["postmaster"]
            BE1["backend processes<br/>(1 per connection)"]
            SB1["shared_buffers 256MB<br/>(data pages)"]
            WB1["WAL buffers"]
            WW["walwriter / checkpointer /<br/>bgwriter / autovacuum"]
            WS["walsender<br/>application_name=pglab-replica"]
            SLOT{{"physical slot<br/>replica_1_slot<br/>(restart_lsn)"}}
            WAL1[("pg_wal/<br/>16MB segments")]
            DATA1[("base/ data files")]
        end

        subgraph REPLICA["Container pglab-replica (hostname postgres-replica)"]
            direction TB
            WR["walreceiver"]
            WAL2[("pg_wal/")]
            SU["startup process<br/>(recovery / redo)"]
            SB2["shared_buffers"]
            DATA2[("base/ data files")]
            BE2["read-only backends<br/>(hot_standby = on)"]
        end
    end

    V1[("volume<br/>postgresql-lab_postgres_primary_data")]
    V2[("volume<br/>postgresql-lab_postgres_replica_data")]

    DBeaver -->|"127.0.0.1:5432<br/>INSERT/UPDATE/DELETE/SELECT"| PM1
    DBeaver -->|"127.0.0.1:5433<br/>SELECT only"| BE2
    Scripts -. "docker compose exec psql / pg_dump" .-> BE1
    Scripts -. "pg_dump stdout" .-> Backups
    Gen -->|"COPY ... FROM STDIN<br/>(batch = 10,000 rows)"| BE1

    PM1 --> BE1
    BE1 -->|"modify pages"| SB1
    BE1 -->|"XLogInsert"| WB1
    WB1 -->|"write + fsync at COMMIT"| WAL1
    WW -->|"flush dirty pages<br/>at checkpoint"| DATA1
    SB1 -.-> WW
    WAL1 -->|"read"| WS
    SLOT -. "keeps WAL >= restart_lsn" .-> WAL1
    WS ==>|"TCP, replication protocol<br/>XLogData messages"| WR
    WR -. "feedback: write/flush/apply LSN,<br/>hot_standby_feedback xmin" .-> WS
    WR -->|"write + fsync"| WAL2
    WAL2 -->|"read records"| SU
    SU -->|"redo into pages"| SB2
    SB2 -->|"restartpoint"| DATA2
    BE2 -->|"read"| SB2

    DATA1 --- V1
    WAL1 --- V1
    DATA2 --- V2
    WAL2 --- V2
```

| Thành phần | Image | Port host | Volume | Vai trò |
| --- | --- | --- | --- | --- |
| `postgres-primary` | `postgresql-lab/postgres-primary:16` (từ `postgres:16-bookworm`) | `127.0.0.1:5432` | `postgresql-lab_postgres_primary_data` → `/var/lib/postgresql/data` | nhận mọi thao tác ghi, sinh WAL, gửi WAL |
| `postgres-replica` | `postgresql-lab/postgres-replica:16` | `127.0.0.1:5433` | `postgresql-lab_postgres_replica_data` → `/var/lib/postgresql/data` (cluster nằm ở `.../pgdata`) | nhận WAL, replay, phục vụ SELECT |
| `data-generator` | `postgresql-lab/data-generator` (từ `python:3.12-slim`) | — | — | nạp dữ liệu vào primary rồi thoát |

## 2. Trình tự khởi động (`docker compose up -d --build`)

```mermaid
sequenceDiagram
    autonumber
    participant DC as docker compose
    participant P as postgres-primary
    participant R as postgres-replica
    participant G as data-generator

    DC->>P: start (volume trống)
    Note over P: docker-entrypoint.sh: initdb<br/>start server TẠM (chỉ unix socket)
    P->>P: 01-create-replication-user.sh<br/>CREATE ROLE replicator REPLICATION<br/>pg_create_physical_replication_slot('replica_1_slot')
    P->>P: 02-extensions.sql, 03-schema.sql, 04-indexes.sql
    Note over P: stop server tạm → start server thật<br/>listen_addresses='*'
    DC->>P: healthcheck: pg_isready -h 127.0.0.1 (TCP)
    P-->>DC: healthy (chỉ khi init xong vì server tạm không nghe TCP)

    par replica
        DC->>R: start (depends_on primary healthy)
        R->>P: pg_basebackup --wal-method=stream --slot=replica_1_slot -R
        P-->>R: toàn bộ data directory + WAL phát sinh trong lúc copy
        Note over R: tạo standby.signal +<br/>primary_conninfo/primary_slot_name<br/>trong postgresql.auto.conf
        R->>R: postgres start → "entering standby mode"
        R->>P: walreceiver: START_REPLICATION SLOT replica_1_slot PHYSICAL x/y
        P-->>R: WAL stream liên tục
    and generator
        DC->>G: start (depends_on primary healthy)
        G->>P: COPY categories, warehouses, users, addresses, products, inventory,<br/>orders, order_items, payments, reviews (commit mỗi batch)
        G->>P: setval(sequences), VACUUM (ANALYZE)
        Note over P,R: mọi thay đổi → WAL → replica tự động
        G-->>DC: exit 0
    end
```

Lần `docker compose up` sau đó (volume đã có dữ liệu): primary bỏ qua init scripts; replica thấy file đánh dấu `.bootstrap-complete` nên chỉ start và **tiếp tục stream từ LSN đã replay cuối cùng** (slot đã giữ lại WAL còn thiếu); generator thấy run `COMPLETED` nên thoát ngay.

## 3. Các process PostgreSQL

Xem process trong container:

```bash
docker compose exec postgres-primary ps -o pid,cmd -u postgres
docker compose exec postgres-replica ps -o pid,cmd -u postgres
```

```text
# primary
      1 postgres -c config_file=/etc/postgresql/postgresql.conf       <- postmaster
     26 postgres: pglab-primary: checkpointer
     27 postgres: pglab-primary: background writer
     29 postgres: pglab-primary: walwriter
     30 postgres: pglab-primary: autovacuum launcher
     31 postgres: pglab-primary: logical replication launcher
     39 postgres: pglab-primary: walsender replicator 192.168.147.3(36738) streaming 1/370010D8
    (+ 1 dòng "postgres: pglab-primary: postgres ecommerce 192.168.147.1(...) idle" cho mỗi connection DBeaver)

# replica
      1 postgres -c config_file=/etc/postgresql/postgresql.conf
     19 postgres: pglab-replica: checkpointer
     20 postgres: pglab-replica: background writer
     21 postgres: pglab-replica: startup recovering 000000010000000100000037   <- file WAL đang replay
     22 postgres: pglab-replica: walreceiver streaming 1/370010D8
```

`000000010000000100000037` là tên WAL segment: 8 hex đầu = **timeline** (`00000001`), 16 hex sau = số segment. Sau một lần failover, timeline tăng lên `00000002`.

`cluster_name` (`pglab-primary` / `pglab-replica`) xuất hiện trong tên process, và tên replica cũng chính là `application_name` trong `pg_stat_replication`.

Từ SQL:

```sql
SELECT pid, backend_type, state, application_name FROM pg_stat_activity ORDER BY backend_type;
```

| Process | Ở đâu | Làm gì |
| --- | --- | --- |
| postmaster | cả hai | process cha, nhận connection và fork backend |
| backend (`client backend`) | cả hai | 1 process / connection, thực thi SQL |
| walwriter | primary | định kỳ ghi WAL buffers xuống `pg_wal` |
| checkpointer | cả hai | checkpoint (primary) / restartpoint (replica): ghi dirty pages xuống data files |
| background writer | cả hai | ghi bớt dirty pages để backend không phải tự ghi |
| autovacuum | primary | VACUUM/ANALYZE tự động (replica không được VACUUM — nó nhận kết quả qua WAL) |
| walsender | primary | đọc WAL, gửi cho replica / pg_basebackup |
| walreceiver | replica | nhận WAL, ghi vào `pg_wal` của replica, gửi feedback |
| startup | replica | đọc WAL và **replay** (redo) vào data pages |

## 4. Mô hình dữ liệu

```mermaid
erDiagram
    users ||--o{ addresses : "has"
    users ||--o{ orders : "places"
    users ||--o{ reviews : "writes"
    categories ||--o{ categories : "parent_id"
    categories ||--o{ products : "contains"
    products ||--o{ inventory : "stocked in"
    warehouses ||--o{ inventory : "holds"
    orders ||--|{ order_items : "contains"
    products ||--o{ order_items : "sold as"
    orders ||--o{ payments : "paid by"
    products ||--o{ reviews : "reviewed in"
    orders |o--o{ reviews : "verifies"

    users {
        bigint id PK
        varchar username UK
        varchar email "UNIQUE lower(email)"
        text password_hash
        varchar full_name
        varchar phone
        date date_of_birth
        char gender "CHECK M/F/O"
        user_status status "ENUM"
        boolean is_email_verified
        integer loyalty_points "CHECK >= 0"
        timestamptz last_login_at
        inet last_login_ip
        jsonb metadata
        timestamptz created_at
        timestamptz updated_at "trigger"
    }
    addresses {
        bigint id PK
        bigint user_id FK
        address_label label "ENUM"
        varchar city
        char country_code "CHECK ^[A-Z]{2}$"
        boolean is_default "partial UNIQUE (user_id) WHERE is_default"
    }
    categories {
        integer id PK
        integer parent_id FK
        varchar name "UNIQUE NULLS NOT DISTINCT (parent_id, name)"
        varchar slug UK
    }
    products {
        bigint id PK
        integer category_id FK
        varchar sku UK
        varchar name
        varchar brand
        numeric price "CHECK >= 0"
        numeric cost
        integer stock_quantity
        product_status status "ENUM"
        text_array tags
        jsonb attributes "GIN jsonb_path_ops"
    }
    warehouses {
        smallint id PK
        varchar code UK
    }
    inventory {
        bigint id PK
        bigint product_id FK
        smallint warehouse_id FK
        integer quantity
        integer reserved_quantity "CHECK <= quantity"
        integer reorder_level
    }
    orders {
        bigint id PK
        bigint user_id FK
        varchar order_number UK
        order_status status "ENUM"
        numeric subtotal
        numeric discount
        numeric shipping_fee
        numeric total_amount "CHECK = subtotal - discount + shipping_fee"
        jsonb shipping_address "snapshot"
        timestamptz created_at
    }
    order_items {
        bigint id PK
        bigint order_id FK
        bigint product_id FK
        integer quantity "CHECK > 0"
        numeric unit_price
        numeric discount
        numeric total_price "CHECK = qty * unit_price - discount"
    }
    payments {
        bigint id PK
        bigint order_id FK
        payment_method payment_method "ENUM"
        numeric amount
        payment_status status "ENUM"
        uuid transaction_id UK
        jsonb provider_response
        timestamptz paid_at "CHECK paid_at iff SUCCEEDED/REFUNDED"
    }
    reviews {
        bigint id PK
        bigint product_id FK
        bigint user_id FK
        bigint order_id FK "NOT indexed (on purpose)"
        smallint rating "CHECK 1..5"
        boolean is_verified_purchase
    }
```

Các quyết định thiết kế đáng chú ý (đọc thêm comment trong [03-schema.sql](../postgres/primary/init/03-schema.sql)):

- **Tiền = `numeric(12,2)`**, không bao giờ dùng `float`. Generator tính bằng *cent* (integer) nên CHECK `total_price = quantity * unit_price - discount` luôn đúng tuyệt đối.
- **`orders.shipping_address` là JSONB snapshot**, không phải FK tới `addresses`: user sửa địa chỉ sau này không được làm thay đổi đơn cũ.
- **`order_items.unit_price`** lưu giá tại thời điểm mua (`products.price` có thể đổi).
- **`products.stock_quantity`** là giá trị *denormalized* của `SUM(inventory.quantity)` — có bài tập kiểm tra độ lệch.
- **Identity `GENERATED BY DEFAULT`** để generator tự cấp id (và sắp xếp id theo thời gian), sau đó `setval` đồng bộ sequence.
- **ENUM có thứ tự**: `'PENDING' < 'CONFIRMED' < … < 'CANCELLED'` — `ORDER BY status` theo thứ tự khai báo, không theo alphabet.
- **Constraint có tên** (`pk_`, `fk_`, `uq_`, `ck_`) để thông báo lỗi dễ đọc.

## 5. Index

Danh sách index hiện có và index **cố ý bỏ trống** nằm ở đầu [04-indexes.sql](../postgres/primary/init/04-indexes.sql). Xem nhanh:

```sql
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' ORDER BY 1, 2;
```

## 6. Cấu hình quan trọng

| File | Nội dung chính |
| --- | --- |
| [postgres/primary/postgresql.conf](../postgres/primary/postgresql.conf) | `wal_level=replica`, `max_wal_senders=10`, `max_replication_slots=10`, `wal_keep_size=512MB`, `max_slot_wal_keep_size=4GB`, `wal_log_hints=on`, `shared_preload_libraries=pg_stat_statements`, `track_io_timing=on`, logging |
| [postgres/primary/pg_hba.conf](../postgres/primary/pg_hba.conf) | `host replication all samenet scram-sha-256` + client `scram-sha-256` |
| [postgres/replica/postgresql.conf](../postgres/replica/postgresql.conf) | `hot_standby=on`, `hot_standby_feedback=on`, `max_standby_streaming_delay=30s`, `wal_receiver_status_interval=1s` |
| `$PGDATA/postgresql.auto.conf` (replica) | `primary_conninfo`, `primary_slot_name` — do `pg_basebackup -R` sinh ra |
| `$PGDATA/standby.signal` (replica) | file rỗng; có file này → server khởi động ở chế độ standby |

```bash
docker compose exec postgres-replica cat /var/lib/postgresql/data/pgdata/postgresql.auto.conf
docker compose exec postgres-replica ls -la /var/lib/postgresql/data/pgdata/standby.signal
```

Giải thích chi tiết từng tham số: [replication.md](replication.md#2-cấu-hình).
