"""reviews: ~75% verified (tied to a real COMPLETED order), the rest unverified."""

from __future__ import annotations

from datetime import timedelta

from .context import Context
from .db import Progress, copy_rows
from .distributions import WeightedSampler, skewed_between
from .orders import Purchase
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


def generate_reviews(ctx: Context, users: UserData, products: ProductData, purchases: list[Purchase]) -> None:
    cfg, rng, now, fake = ctx.cfg, ctx.rng, ctx.now, ctx.fake
    target = cfg.num_reviews
    if target == 0:
        return
    print("Generating reviews (planning)...", flush=True)
    rating_samplers = {q: WeightedSampler((1, 2, 3, 4, 5), w) for q, w in RATING_WEIGHTS.items()}
    extra_sentences = [fake.sentence(nb_words=12) for _ in range(2000)]
    n_products = len(products.price_cents)
    seen: set[int] = set()
    planned = []   # (created_at, product_id, user_id, order_id, verified)

    for p in purchases:
        key = p.user_id * (n_products + 1) + p.product_id
        if key in seen:
            continue
        seen.add(key)
        created = min(p.ordered_at + timedelta(days=rng.uniform(3, 45)), now)
        planned.append((created, p.product_id, p.user_id, p.order_id, True))
        if len(planned) >= target:
            break

    attempts = 0
    while len(planned) < target and attempts < target * 5:
        attempts += 1
        user_id = users.pick_buyer(ctx) if rng.random() < 0.5 else rng.randint(1, cfg.num_users)
        product_id = products.popularity.sample(rng)
        key = user_id * (n_products + 1) + product_id
        if key in seen:
            continue
        seen.add(key)
        lo = max(users.created_at[user_id - 1], products.created_at[product_id - 1])
        planned.append((skewed_between(rng, lo, now, 0.6), product_id, user_id, None, False))

    # Insert in chronological order -> reviews.id correlates with created_at
    planned.sort(key=lambda r: r[0])

    progress = Progress("Reviews", len(planned))
    for start, end in ctx.batches(len(planned)):
        rows = []
        for created, product_id, user_id, order_id, verified in planned[start:end]:
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
    verified_count = sum(1 for r in planned if r[4])
    progress.finish(f"{verified_count:,} verified purchases")
