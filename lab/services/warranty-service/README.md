# Warranty Service

Sở hữu **Warranty, coverage và expiry**, database **warranty_db**. Đây là application FastAPI độc lập; không truy cập database của service khác.

Nhận REST POST /internal/warranties từ Vehicle; không consume Kafka để tạo DEFAULT. Publish warranty.created, warranty.activated, warranty.expired.

create_default và expiry_loop trong app/services/warranties.py; DEFAULT warranty được bảo vệ bởi unique vehicle_id + warranty_type.

API/validation ở `app/api`, `app/schemas`; persistence ở `app/models`, `app/repositories`; business transaction ở `app/services`. Entrypoint `app/main.py` chỉ lắp router/handlers vào runtime dùng chung. Docker build từ root repo để copy `common/platform_common`; tất cả code được đóng gói vào image.

```sh
# Chạy từ root repo
# Dependencies và migrations tự khởi tạo qua Compose
docker compose up -d --build warranty-service
docker compose exec warranty-service alembic current
docker compose exec -T warranty-service pytest -q tests
docker compose logs -f warranty-service
```

Mỗi service có bảng outbox/processed-events/idempotency riêng. Runtime dùng chung nằm ở [common/platform_common](../../common/platform_common), config qua env trong [Compose](../../docker-compose.yml). PostgreSQL schema test cô lập với application đang chạy.

Xem [README toàn hệ thống](../../README.md) để chạy demo, curl, seed, failure drills và hiểu các giới hạn consistency. `/health`, `/ready`, `/docs` dùng port 8000 bên trong container.
