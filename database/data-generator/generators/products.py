"""products + inventory."""

from __future__ import annotations

import json
import math
from array import array
from dataclasses import dataclass
from datetime import timedelta

from .catalog import Catalog, LeafCategory
from .context import Context
from .db import Progress, copy_rows
from .distributions import WeightedSampler, days_ago, skewed_between, to_us
from .reference import (ADJECTIVES, BENEFITS, BOOK_LANGUAGE_WEIGHTS, BOOK_LANGUAGES, BOOK_WORDS_A, BOOK_WORDS_B,
                        CAR_MAKES, COLOR_WEIGHTS, COLORS, FEATURES, HOME_MATERIALS, MATERIALS, PRODUCT_TAG_WEIGHTS,
                        PRODUCT_TAGS)

PRODUCT_COLUMNS = ("id", "category_id", "sku", "name", "description", "brand", "price", "cost", "stock_quantity",
                   "status", "weight_grams", "tags", "attributes", "created_at", "updated_at")
INVENTORY_COLUMNS = ("product_id", "warehouse_id", "quantity", "reserved_quantity", "reorder_level",
                     "last_restocked_at", "updated_at")

QUALITY_BAD, QUALITY_NORMAL, QUALITY_GREAT = 0, 1, 2


@dataclass
class ProductData:
    price_cents: array            # index = product_id - 1
    popularity: WeightedSampler[int]
    quality: bytearray            # hidden "true quality" -> drives review ratings
    created_us: array             # epoch microseconds, index = product_id - 1


class _AttributeBuilder:
    """Category-specific JSONB attributes -> different keys per category (jsonb ? 'key' lessons)."""

    def __init__(self, ctx: Context):
        self.rng = ctx.rng
        self.fake = ctx.fake
        self.color = WeightedSampler(COLORS, COLOR_WEIGHTS)
        self.book_lang = WeightedSampler(BOOK_LANGUAGES, BOOK_LANGUAGE_WEIGHTS)
        self.authors = [ctx.fake.name() for _ in range(3000)]

    def build(self, lc: LeafCategory, brand: str) -> dict:
        rng, kind, code = self.rng, lc.top.kind, lc.leaf.code
        attrs: dict = {"brand": brand}
        if kind == "electronics":
            attrs |= {"color": self.color.sample(rng), "warranty_months": rng.choice((6, 12, 12, 24, 36))}
            if code == "PHN":
                attrs["specs"] = {"storage_gb": rng.choice((64, 128, 128, 256, 512, 1024)),
                                  "ram_gb": rng.choice((4, 6, 8, 8, 12, 16)),
                                  "screen_inches": round(rng.uniform(5.8, 6.9), 1), "5g": rng.random() < 0.7}
            elif code == "LAP":
                attrs["specs"] = {"ram_gb": rng.choice((8, 16, 16, 32, 64)),
                                  "storage_gb": rng.choice((256, 512, 512, 1024, 2048)),
                                  "cpu": rng.choice(("Intel Core i5", "Intel Core i7", "AMD Ryzen 5", "AMD Ryzen 7",
                                                     "Apple M3", "Apple M4")),
                                  "screen_inches": rng.choice((13.3, 14.0, 15.6, 16.0, 17.3))}
            elif code == "AUD":
                attrs["specs"] = {"wireless": rng.random() < 0.8, "noise_cancelling": rng.random() < 0.4,
                                  "battery_hours": rng.choice((6, 8, 12, 20, 30, 40))}
            else:
                attrs["specs"] = {"megapixels": rng.choice((12, 20, 24, 33, 45, 61)),
                                  "video": rng.choice(("1080p", "4K", "4K", "8K"))}
        elif kind == "fashion":
            size = str(rng.randint(36, 46)) if code == "SHO" else rng.choice(("XS", "S", "M", "M", "L", "L", "XL", "XXL"))
            attrs |= {"color": self.color.sample(rng), "size": size, "material": rng.choice(MATERIALS),
                      "gender": rng.choice(("men", "women", "unisex")) if code in ("SHO", "ACC")
                      else ("men" if code == "MEN" else "women")}
        elif kind == "home":
            attrs |= {"color": self.color.sample(rng), "material": rng.choice(HOME_MATERIALS),
                      "dimensions_cm": {"w": rng.randint(10, 200), "h": rng.randint(5, 200), "d": rng.randint(5, 100)}}
            if code == "KIT":
                attrs["power_watts"] = rng.choice((600, 800, 1000, 1200, 1500, 1800))
        elif kind == "beauty":
            attrs |= {"volume_ml": rng.choice((15, 30, 50, 100, 200, 400)),
                      "skin_type": rng.choice(("all", "dry", "oily", "combination", "sensitive")),
                      "vegan": rng.random() < 0.35, "cruelty_free": rng.random() < 0.6}
        elif kind == "sports":
            attrs |= {"color": self.color.sample(rng), "material": rng.choice(MATERIALS + ("Aluminium", "Carbon")),
                      "level": rng.choice(("beginner", "intermediate", "pro"))}
        elif kind == "books":
            attrs |= {"author": rng.choice(self.authors),
                      "format": rng.choice(("Paperback", "Paperback", "Hardcover", "eBook", "Audiobook")),
                      "pages": rng.randint(24 if code == "CHB" else 120, 64 if code == "CHB" else 900),
                      "language": self.book_lang.sample(rng),
                      "isbn": f"978{rng.randint(0, 9_999_999_999):010d}"}
        elif kind == "toys":
            attrs |= {"age_min": rng.choice((3, 6, 8, 12, 14)), "pieces": rng.choice((1, 50, 100, 500, 1000, 2000)),
                      "battery_required": rng.random() < 0.25}
        elif kind == "grocery":
            attrs |= {"net_weight_g": rng.choice((50, 100, 250, 500, 1000)), "organic": rng.random() < 0.25,
                      "pack_size": rng.choice((1, 1, 6, 12, 24)), "shelf_life_days": rng.choice((30, 90, 180, 365, 730))}
            if rng.random() < 0.5:
                attrs["flavor"] = rng.choice(("original", "chocolate", "vanilla", "spicy", "sea salt", "berry"))
        elif kind == "automotive":
            attrs |= {"compatible_makes": sorted(rng.sample(CAR_MAKES, rng.randint(1, 4))),
                      "warranty_months": rng.choice((0, 6, 12, 24))}
        elif kind == "health":
            attrs |= {"form": rng.choice(("capsule", "tablet", "powder", "gummy", "device")),
                      "servings": rng.choice((30, 60, 90, 120)), "vegan": rng.random() < 0.3}
        if rng.random() < 0.08:
            attrs["origin_country"] = rng.choice(("US", "CN", "VN", "DE", "JP", "KR", "IT"))
        return attrs


def _price_cents(rng, lo: float, hi: float) -> int:
    # log-uniform, skewed toward the cheap end of the category's range
    price = math.exp(math.log(lo) + (math.log(hi) - math.log(lo)) * (rng.random() ** 1.4))
    if price >= 10 and rng.random() < 0.6:
        return int(price) * 100 + 99              # psychological pricing: 49.99
    return max(100, int(round(price * 100)))


def generate_products(ctx: Context, catalog: Catalog) -> ProductData:
    cfg, rng, now = ctx.cfg, ctx.rng, ctx.now
    n = cfg.num_products
    attr_builder = _AttributeBuilder(ctx)
    status_sampler = WeightedSampler(("ACTIVE", "OUT_OF_STOCK", "DISCONTINUED", "DRAFT"), (85, 5, 7, 3))
    tag_sampler = WeightedSampler(PRODUCT_TAGS, PRODUCT_TAG_WEIGHTS)
    n_warehouses = len(catalog.warehouse_ids)

    created_at = sorted(skewed_between(rng, days_ago(now, cfg.history_days + 365), now - timedelta(days=1), 0.8)
                        for _ in range(n))

    # Inventory rows per product: NUM_INVENTORY spread as evenly as possible, max one per warehouse
    num_inventory = min(cfg.num_inventory, n * n_warehouses)
    base, remainder = divmod(num_inventory, n)
    extra = set(rng.sample(range(n), remainder)) if remainder else set()

    price_cents = array("q", bytes(8 * n))
    quality = bytearray(n)
    statuses: list[str] = [""] * n

    progress = Progress("Products", n)
    inventory_total = 0
    for start, end in ctx.batches(n):
        product_rows, inventory_rows = [], []
        for idx in range(start, end):
            pid = idx + 1
            lc = catalog.leaf_sampler.sample(rng)
            leaf, top = lc.leaf, lc.top
            brand = rng.choice(top.brands)
            noun = rng.choice(leaf.nouns)
            if top.kind == "books":
                name = f"The {rng.choice(BOOK_WORDS_A)} {rng.choice(BOOK_WORDS_B)} ({noun})"
            else:
                model = rng.choice((f"{rng.randint(1, 20)}", f"X{rng.randint(10, 99)}", f"Gen {rng.randint(2, 6)}",
                                    f"{rng.randint(2019, now.year)}", f"S{rng.randint(100, 999)}"))
                name = f"{brand} {rng.choice(ADJECTIVES)} {noun} {model}"

            status = status_sampler.sample(rng)
            statuses[idx] = status
            price = _price_cents(rng, leaf.price_min, leaf.price_max)
            price_cents[idx] = price
            cost = int(price * rng.uniform(0.35, 0.8))
            r = rng.random()
            quality[idx] = QUALITY_BAD if r < 0.15 else (QUALITY_GREAT if r > 0.8 else QUALITY_NORMAL)

            # inventory for this product
            k = min(base + (1 if idx in extra else 0), n_warehouses)
            stock = 0
            for wh in rng.sample(catalog.warehouse_ids, k):
                if status in ("OUT_OF_STOCK", "DRAFT") or (status == "DISCONTINUED" and rng.random() < 0.7):
                    qty = 0
                elif rng.random() < 0.08:
                    qty = rng.randint(0, 10)                     # low stock
                else:
                    qty = int(rng.lognormvariate(3.5, 1.0))     # median ~33, long tail
                reserved = rng.randint(0, min(qty, 5)) if qty and rng.random() < 0.3 else 0
                restocked = now - timedelta(days=rng.random() * 120) if qty else None
                inventory_rows.append((pid, wh, qty, reserved, rng.choice((5, 10, 10, 20, 50)), restocked,
                                       restocked or created_at[idx]))
                stock += qty

            tags = []
            if rng.random() < 0.6:
                tags = sorted({tag_sampler.sample(rng) for _ in range(rng.randint(1, 3))})
            description = None
            if rng.random() < 0.9:
                f1, f2 = rng.sample(FEATURES, 2)
                description = f"The {brand} {noun} offers {f1} and {f2}. {rng.choice(BENEFITS)}"

            created = created_at[idx]
            product_rows.append((
                pid, lc.id, f"{top.code}-{leaf.code}-{pid:07d}", name, description, brand,
                f"{price // 100}.{price % 100:02d}", f"{cost // 100}.{cost % 100:02d}", stock, status,
                rng.randint(*top.weight_grams) if rng.random() < 0.95 else None,
                tags, json.dumps(attr_builder.build(lc, brand), separators=(",", ":")),
                created, skewed_between(rng, created, now, 0.5),
            ))

        copy_rows(ctx.conn, "products", PRODUCT_COLUMNS, product_rows)
        copy_rows(ctx.conn, "inventory", INVENTORY_COLUMNS, inventory_rows)
        ctx.conn.commit()
        inventory_total += len(inventory_rows)
        progress.advance(len(product_rows))
    progress.finish(f"{inventory_total:,} inventory rows")

    created_us = array("q", map(to_us, created_at))
    del created_at

    # Popularity: Zipf over a random ranking of products, damped for expensive
    # items; DRAFT products never sell, DISCONTINUED ones rarely.
    # Same formula as distributions.zipf_weights (1 / (rank + 50)^1.1), computed
    # inline into arrays so 5M products cost ~80 MB instead of ~500 MB of lists.
    ranking = array("q", range(n))
    rng.shuffle(ranking)
    weights = array("d", bytes(8 * n))
    for rank, idx in enumerate(ranking, start=1):
        w = (1.0 / ((rank + 50) ** 1.1)) / math.sqrt(1 + price_cents[idx] / 20_000)
        if statuses[idx] == "DRAFT":
            w = 0.0
        elif statuses[idx] == "DISCONTINUED":
            w *= 0.3
        weights[idx] = w
    del ranking, statuses
    popularity = WeightedSampler(range(1, n + 1), weights)

    return ProductData(price_cents, popularity, quality, created_us)
