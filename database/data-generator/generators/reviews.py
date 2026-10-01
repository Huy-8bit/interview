"""reviews: ~75% verified (tied to a real COMPLETED order), the rest unverified."""

from __future__ import annotations

from array import array
from datetime import datetime, timedelta

from .context import Context
from .db import Progress, copy_rows
from .distributions import UTC, WeightedSampler, from_us, skewed_between, to_us
from .orders import Purchases
from .products import QUALITY_BAD, QUALITY_GREAT, ProductData
from .reference import REVIEW_SENTENCES, REVIEW_TITLES
from .users import UserData

REVIEW_COLUMNS = ("product_id", "user_id", "order_id", "rating", "title", "body", "is_verified_purchase",
                  "helpful_count", "created_at")
# J-shaped rating distributions (lots of 5s and a bump at 1), per hidden product quality
RATING_WEIGHTS = {
    QUALITY_BAD: (30, 18, 20, 17, 15),
    1: (7, 5, 11, 27, 50),
    QUALITY_GREAT: (2, 2, 5, 21, 70),
}


def _sentiment(rating: int) -> str:
    return "positive" if rating >= 4 else ("neutral" if rating == 3 else "negative")


def generate_reviews(ctx: Context, users: UserData, products: ProductData, purchases: Purchases) -> None:
    cfg, rng, now, fake = ctx.cfg, ctx.rng, ctx.now, ctx.fake
    target = cfg.num_reviews
    if target == 0:
        return
    print("Generating reviews (planning)...", flush=True)
    rating_samplers = {q: WeightedSampler((1, 2, 3, 4, 5), w) for q, w in RATING_WEIGHTS.items()}
    extra_sentences = [fake.sentence(nb_words=12) for _ in range(2000)]
    n_products = len(products.price_cents)
    seen: set[int] = set()
    # Planned reviews as parallel arrays (order_id 0 = unverified, no order)
    p_created, p_product, p_user, p_order = array("q"), array("q"), array("q"), array("q")

    def plan(created: datetime, product_id: int, user_id: int, order_id: int) -> None:
        p_created.append(to_us(created))
        p_product.append(product_id)
        p_user.append(user_id)
        p_order.append(order_id)

    for i in range(len(purchases)):
        user_id, product_id = purchases.user_id[i], purchases.product_id[i]
        key = user_id * (n_products + 1) + product_id
        if key in seen:
            continue
        seen.add(key)
        ordered_at = datetime.fromtimestamp(purchases.ordered_ts[i], UTC)
        created = min(ordered_at + timedelta(days=rng.uniform(3, 45)), now)
        plan(created, product_id, user_id, purchases.order_id[i])
        if len(p_order) >= target:
            break
    verified_count = len(p_order)

    attempts = 0
    while len(p_order) < target and attempts < target * 5:
        attempts += 1
        user_id = users.pick_buyer(ctx) if rng.random() < 0.5 else rng.randint(1, cfg.num_users)
        product_id = products.popularity.sample(rng)
        key = user_id * (n_products + 1) + product_id
        if key in seen:
            continue
        seen.add(key)
        lo = from_us(max(users.created_us[user_id - 1], products.created_us[product_id - 1]))
        plan(skewed_between(rng, lo, now, 0.6), product_id, user_id, 0)
    del seen

    # Insert in chronological order -> reviews.id correlates with created_at
    # (stable sort, like list.sort, so equal timestamps keep their planning order)
    chrono = array("q", sorted(range(len(p_order)), key=p_created.__getitem__))

    progress = Progress("Reviews", len(chrono))
    for start, end in ctx.batches(len(chrono)):
        rows = []
        for j in chrono[start:end]:
            product_id, user_id = p_product[j], p_user[j]
            order_id = p_order[j] or None
            verified = order_id is not None
            created = from_us(p_created[j])
            rating = rating_samplers[products.quality[product_id - 1]].sample(rng)
            mood = _sentiment(rating)
            title = rng.choice(REVIEW_TITLES[mood]) if rng.random() < 0.9 else None
            body = None
            if rng.random() < 0.8:
                parts = rng.sample(REVIEW_SENTENCES[mood], rng.randint(1, 3))
                if rng.random() < 0.3:
                    parts.append(rng.choice(extra_sentences))
                body = " ".join(parts)
            helpful = 0 if rng.random() < 0.7 else int(rng.expovariate(1 / 8)) + (5 if body and len(body) > 120 else 0)
            rows.append((product_id, user_id, order_id, rating, title, body, verified, helpful, created))
        copy_rows(ctx.conn, "reviews", REVIEW_COLUMNS, rows)
        ctx.conn.commit()
        progress.advance(len(rows))
    progress.finish(f"{verified_count:,} verified purchases")
