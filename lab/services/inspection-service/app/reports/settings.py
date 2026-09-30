from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class ReportSettings(BaseSettings):
    """Report pipeline knobs shared by the API dispatcher and the Celery workers."""

    model_config = SettingsConfigDict(extra="ignore")

    # ';'-separated failover list; kombu reconnects to the next node when one dies.
    rabbitmq_urls: str = "amqp://lab:lab_rabbitmq_password@rabbitmq-1:5672//;amqp://lab:lab_rabbitmq_password@rabbitmq-2:5672//;amqp://lab:lab_rabbitmq_password@rabbitmq-3:5672//"
    rabbitmq_heartbeat: int = Field(10, ge=0, le=600)
    report_max_retries: int = Field(3, ge=0, le=10)
    report_retry_base_seconds: float = Field(2, ge=1, le=60)
    report_retry_max_seconds: float = Field(60, ge=1, le=3600)
    report_soft_time_limit: int = Field(20, ge=1, le=600)
    report_time_limit: int = Field(30, ge=2, le=900)
    # Emulated rendering cost (charts, photos, fonts); the lab PDF itself is tiny.
    report_render_cost_ms: int = Field(300, ge=0, le=60000)
    report_dispatch_interval: float = Field(0.5, gt=0, le=10)
    report_dispatch_batch: int = Field(20, ge=1, le=500)
    report_dispatch_retry_max_seconds: float = Field(30, gt=0, le=600)
    report_metrics_port: int = Field(9808, ge=1024, le=65535)

    @model_validator(mode="after")
    def hard_limit_after_soft(self):
        if self.report_time_limit <= self.report_soft_time_limit:
            raise ValueError("REPORT_TIME_LIMIT must exceed REPORT_SOFT_TIME_LIMIT so the task can clean up first")
        return self
