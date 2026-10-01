"""Non-uniform random distributions that make the data look like a real shop.

Skewed data is the whole point of the lab: the query planner chooses between
Seq Scan / Index Scan / Bitmap Scan based on *selectivity*, and selectivity is
only interesting when values are not uniformly distributed.
"""

from __future__ import annotations

import bisect
import math
import random
from array import array
from datetime import datetime, timedelta, timezone
from itertools import accumulate
from typing import Generic, Sequence, TypeVar

T = TypeVar("T")

UTC = timezone.utc
# Relative traffic per hour of day (UTC): quiet at night, peaks in the evening.
HOUR_WEIGHTS = [2, 1, 1, 1, 1, 2, 3, 5, 6, 7, 7, 8, 9, 8, 7, 7, 8, 9, 11, 13, 14, 12, 8, 4]


class WeightedSampler(Generic[T]):
    """O(log n) weighted sampling with pre-computed cumulative weights.

    `items` may be a range or an array (kept as is, no copy) so that sampling
    over millions of products costs 8 bytes per item instead of a Python list.
    """

    def __init__(self, items: Sequence[T], weights: Sequence[float]):
        if len(items) != len(weights) or not items:
            raise ValueError("items and weights must be non-empty and the same length")
        self.items = items if isinstance(items, (range, array)) else list(items)
        self.cum = array("d", accumulate(weights))
        self.total = self.cum[-1]
        if self.total <= 0:
            raise ValueError("sum of weights must be > 0")

    def sample(self, rng: random.Random) -> T:
        idx = bisect.bisect_right(self.cum, rng.random() * self.total)
        return self.items[min(idx, len(self.items) - 1)]


def zipf_weights(n: int, s: float = 1.1, offset: int = 50) -> list[float]:
    """Weight of the item at popularity rank r (1 = most popular): 1 / (r + offset)^s.

    With n=100k, s=1.1, offset=50: the top 1% of items receive ~50% of the
    picks, the top 20% ~85%, and ~9% of items are never picked in 1.5M draws.
    """
    return [1.0 / ((rank + offset) ** s) for rank in range(1, n + 1)]


def poisson(rng: random.Random, lam: float) -> int:
    """Knuth's algorithm; fine for the small lambdas used here."""
    if lam <= 0:
        return 0
    limit, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= rng.random()
        if p <= limit:
            return k
        k += 1


def random_time_of_day(rng: random.Random, day: datetime, hour_sampler: WeightedSampler[int]) -> datetime:
    """Keep the date of `day`, replace the time with a realistic time of day."""
    hour = hour_sampler.sample(rng)
    return day.replace(hour=hour, minute=rng.randrange(60), second=rng.randrange(60),
                       microsecond=rng.randrange(1_000_000))


def skewed_between(rng: random.Random, lo: datetime, hi: datetime, recency: float = 0.7) -> datetime:
    """A datetime in [lo, hi]; recency < 1 skews towards `hi` (business growth)."""
    if hi <= lo:
        return hi
    frac = rng.random() ** recency
    return lo + (hi - lo) * frac


def holiday_season_between(rng: random.Random, lo: datetime, hi: datetime) -> datetime | None:
    """A datetime inside a Black Friday -> Christmas window (Nov 20 - Dec 31) within [lo, hi]."""
    windows = []
    for year in range(lo.year, hi.year + 1):
        start = max(lo, datetime(year, 11, 20, tzinfo=UTC))
        end = min(hi, datetime(year, 12, 31, 23, 59, tzinfo=UTC))
        if end > start:
            windows.append((start, end))
    if not windows:
        return None
    start, end = rng.choice(windows)
    return start + (end - start) * rng.random()


def cents_to_str(cents: int) -> str:
    """Integer cents -> '1234.56'. Money is computed in integer cents so that the
    CHECK constraints (total = qty * price - discount) hold exactly."""
    sign = "-" if cents < 0 else ""
    cents = abs(cents)
    return f"{sign}{cents // 100}.{cents % 100:02d}"


def days_ago(now: datetime, days: float) -> datetime:
    return now - timedelta(days=days)


# Timestamps kept for millions of rows are stored as integer microseconds since
# the epoch in an array('q'): 8 bytes each instead of ~56 for a datetime object,
# and (unlike float timestamps) the round trip is exact.
_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
_ONE_US = timedelta(microseconds=1)


def to_us(dt: datetime) -> int:
    return (dt - _EPOCH) // _ONE_US


def from_us(us: int) -> datetime:
    return _EPOCH + timedelta(microseconds=us)
