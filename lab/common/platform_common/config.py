from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    service_name: str
    write_database_url: str = Field(validation_alias=AliasChoices("WRITE_DATABASE_URL", "DATABASE_URL", "write_database_url", "database_url"))
    read_database_url: str = ""
    redis_cluster_nodes: str
    kafka_bootstrap_servers: str
    kafka_consumer_group: str = ""
    log_level: str = "INFO"
    cache_ttl: int = Field(default=60, ge=1)
    idempotency_ttl: int = Field(default=86400, ge=1)
    lock_timeout: int = Field(default=30, ge=1)
    db_pool_size: int = Field(default=5, ge=1)
    db_max_overflow: int = Field(default=5, ge=0)
    db_pool_timeout: float = Field(default=3, gt=0)
    db_statement_timeout_ms: int = Field(default=10000, ge=100)
    db_read_timeout: float = Field(default=3, gt=0)
    redis_timeout: float = Field(default=0.5, gt=0)
    redis_operation_timeout: float = Field(default=2, gt=0)
    http_connect_timeout: float = Field(default=1, gt=0)
    http_timeout: float = Field(default=2, gt=0)
    http_max_connections: int = Field(default=20, ge=1)
    http_retries: int = Field(default=2, ge=0, le=5)
    warranty_service_url: str = "http://warranty-service:8000"
    default_warranty_days: int = Field(default=1095, ge=1)
    warranty_expiry_interval: float = Field(default=30, gt=0)
    outbox_interval: float = Field(default=0.5, gt=0)
    outbox_retry_max_seconds: float = Field(default=60, gt=0)
    kafka_send_timeout: float = Field(default=5, gt=0)
    kafka_request_timeout_ms: int = Field(default=10000, ge=1000)
    kafka_retry_backoff_ms: int = Field(default=200, ge=1)
    consumer_max_retries: int = Field(default=4, ge=0, le=8)
    retry_base_seconds: float = Field(default=1, gt=0)
    consumer_max_poll_interval_ms: int = Field(default=300000, ge=1000)
    consumer_fetch_timeout: float = Field(default=15, ge=2)
    consumer_stall_timeout: float = Field(default=15, ge=2)
    background_workers: bool = True
    lab_mode: bool = False

    @property
    def database_url(self):
        # Backward-compatible alias for existing lab fixtures; always the writer.
        return self.write_database_url
