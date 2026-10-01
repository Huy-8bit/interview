"""Runtime configuration, read from environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass


def _env_int(name: str, default: int, minimum: int = 0) -> int:
    value = int(os.getenv(name, str(default)))
    if value < minimum:
        raise ValueError(f"{name} must be >= {minimum}, got {value}")
    return value


def _env_float(name: str, default: float) -> float:
    return float(os.getenv(name, str(default)))


def _env_bool(name: str, default: bool) -> bool:
    return os.getenv(name, str(default)).strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Config:
    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str

    auto_generate: bool
    reset_data: bool
    seed: int
    batch_size: int
    faker_locale: str

    num_users: int
    num_products: int
    num_orders: int
    num_order_items: int
    num_inventory: int
    num_reviews: int
    heavy_user_share: float
    heavy_user_order_share: float

    # How far back in time orders go (users/products start one year earlier)
    history_days: int = 3 * 365

    @property
    def avg_items_per_order(self) -> float:
        return self.num_order_items / self.num_orders if self.num_orders else 0.0

    @classmethod
    def from_env(cls) -> "Config":
        cfg = cls(
            db_host=os.getenv("DB_HOST", "localhost"),
            db_port=_env_int("DB_PORT", 5432, 1),
            db_name=os.getenv("DB_NAME", "ecommerce"),
            db_user=os.getenv("DB_USER", "postgres"),
            db_password=os.getenv("DB_PASSWORD", "postgres"),
            auto_generate=_env_bool("AUTO_GENERATE", True),
            reset_data=_env_bool("RESET_DATA", False),
            seed=_env_int("SEED", 42),
            batch_size=_env_int("BATCH_SIZE", 10_000, 1),
            faker_locale=os.getenv("FAKER_LOCALE", "en_US"),
            num_users=_env_int("NUM_USERS", 100_000, 1),
            num_products=_env_int("NUM_PRODUCTS", 100_000, 1),
            num_orders=_env_int("NUM_ORDERS", 500_000),
            num_order_items=_env_int("NUM_ORDER_ITEMS", 1_500_000),
            num_inventory=_env_int("NUM_INVENTORY", 100_000),
            num_reviews=_env_int("NUM_REVIEWS", 300_000),
            heavy_user_share=_env_float("HEAVY_USER_SHARE", 0.20),
            heavy_user_order_share=_env_float("HEAVY_USER_ORDER_SHARE", 0.70),
        )
        if cfg.num_orders and cfg.num_order_items < cfg.num_orders:
            raise ValueError("NUM_ORDER_ITEMS must be >= NUM_ORDERS (every order has at least one line)")
        if not 0 < cfg.heavy_user_share < 1 or not 0 <= cfg.heavy_user_order_share <= 1:
            raise ValueError("HEAVY_USER_SHARE must be in (0,1) and HEAVY_USER_ORDER_SHARE in [0,1]")
        return cfg

    def conninfo(self) -> str:
        return (
            f"host={self.db_host} port={self.db_port} dbname={self.db_name} "
            f"user={self.db_user} password={self.db_password} application_name=data-generator"
        )
