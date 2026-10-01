"""Shared state passed to every generator step."""

from __future__ import annotations

import random
import re
import unicodedata
import uuid
from dataclasses import dataclass
from datetime import datetime

import psycopg
from faker import Faker

from .config import Config
from .distributions import HOUR_WEIGHTS, WeightedSampler


@dataclass
class Context:
    cfg: Config
    conn: psycopg.Connection
    rng: random.Random
    fake: Faker
    now: datetime
    hour_sampler: WeightedSampler[int]

    @classmethod
    def create(cls, cfg: Config, conn: psycopg.Connection, now: datetime) -> "Context":
        Faker.seed(cfg.seed)
        return cls(
            cfg=cfg,
            conn=conn,
            rng=random.Random(cfg.seed),
            fake=Faker(cfg.faker_locale),
            now=now,
            hour_sampler=WeightedSampler(list(range(24)), HOUR_WEIGHTS),
        )

    def uuid4(self) -> uuid.UUID:
        """Deterministic (seeded) UUIDv4."""
        return uuid.UUID(int=self.rng.getrandbits(128), version=4)

    def batches(self, total: int):
        """Yield (start, end) half-open ranges of size BATCH_SIZE."""
        size = self.cfg.batch_size
        for start in range(0, total, size):
            yield start, min(start + size, total)


_NON_ALNUM = re.compile(r"[^a-z0-9]+")


def ascii_slug(text: str, sep: str = "") -> str:
    """'Nguyễn Đức' -> 'nguyenduc' ; "O'Connor" -> 'oconnor'."""
    text = text.replace("đ", "d").replace("Đ", "D")
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii").lower()
    return _NON_ALNUM.sub(sep, text).strip(sep)
