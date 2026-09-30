from typing import Literal

from pydantic import AliasChoices, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Config(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore", populate_by_name=True)

    metrics_port: int = Field(9101, ge=1024, le=65535)
    load_test_mode: bool = False
    load_test_duration_seconds: int = Field(180, ge=10, le=900)
    load_test_max_vehicles: int = Field(1000, ge=1, le=10000)
    enabled: bool = Field(True, validation_alias="TRAFFIC_ENABLED")
    mode: Literal["continuous", "scenario"] = Field("continuous", validation_alias="TRAFFIC_MODE")
    virtual_users: int = Field(5, ge=1, le=100, validation_alias=AliasChoices("VIRTUAL_USERS", "TRAFFIC_CONCURRENCY"))
    interval_ms: int = Field(2000, ge=0, le=3600000, validation_alias="TRAFFIC_INTERVAL_MS")
    timeout: float = Field(5, gt=0, le=60, validation_alias="REQUEST_TIMEOUT_SECONDS")
    max_retries: int = Field(3, ge=0, le=10, validation_alias="MAX_RETRIES")
    backoff_ms: int = Field(200, ge=0, le=10000, validation_alias="RETRY_BACKOFF_MS")
    duplicate_rate: float = Field(0.05, ge=0, le=1, validation_alias="DUPLICATE_REQUEST_RATE")
    delete_rate: float = Field(0.01, ge=0, le=1, validation_alias="DELETE_RATE")
    fail_rate: float = Field(0.30, ge=0, le=1, validation_alias="FAIL_INSPECTION_RATE")
    error_rate: float = Field(0.05, ge=0, le=1, validation_alias="TRAFFIC_ERROR_RATE")
    convergence_timeout: float = Field(45, gt=0, le=300, validation_alias="CONVERGENCE_TIMEOUT_SECONDS")
    flow_timeout: float = Field(120, gt=0, le=900, validation_alias="FLOW_TIMEOUT_SECONDS")
    summary_interval: float = Field(30, ge=1, le=300, validation_alias="SUMMARY_INTERVAL_SECONDS")
    replica_delays: str = Field("0,100,500,1000", validation_alias="REPLICA_READ_DELAYS_MS")
    status_file: str = Field("/tmp/traffic-generator-status.json", validation_alias="TRAFFIC_STATUS_FILE")
    vehicle_url: str = Field("http://vehicle-service:8000", validation_alias="VEHICLE_SERVICE_URL")
    warranty_url: str = Field("http://warranty-service:8000", validation_alias="WARRANTY_SERVICE_URL")
    inspection_url: str = Field("http://inspection-service:8000", validation_alias="INSPECTION_SERVICE_URL")
    repair_url: str = Field("http://repair-service:8000", validation_alias="REPAIR_SERVICE_URL")

    @field_validator("replica_delays")
    @classmethod
    def delays_valid(cls, value):
        delays = [int(s.strip()) for s in value.split(",")]
        if not 1 <= len(delays) <= 10 or delays != sorted(set(delays)) or delays[0] != 0 or delays[-1] > 10000:
            raise ValueError("Replica delays must be sorted unique milliseconds, starting at 0, max 10000")
        return value

    @property
    def urls(self):
        return {s: getattr(self, s + "_url").rstrip("/") for s in ("vehicle", "warranty", "inspection", "repair")}
