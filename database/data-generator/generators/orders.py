"""orders + order_items + payments.

Two passes:
  1. headers: (created_at, user, status) for every order - small arrays only
  2. sort headers by created_at and emit orders in that order, so orders.id
     grows with created_at like in a real system (high pg_stats.correlation)
"""

from __future__ import annotations

import json
from array import array
from dataclasses import dataclass
from datetime import datetime, timedelta

from .context import Context
from .db import Progress, copy_rows
from .distributions import (UTC, WeightedSampler, cents_to_str, from_us, holiday_season_between, poisson,
                            random_time_of_day, skewed_between)
from .products import ProductData
from .reference import COUPON_WEIGHTS, COUPONS
from .users import UserData

ORDER_COLUMNS = ("id", "user_id", "order_number", "status", "subtotal", "discount", "shipping_fee", "total_amount",
                 "currency", "coupon_code", "shipping_address", "note", "created_at", "updated_at")
ITEM_COLUMNS = ("order_id", "product_id", "quantity", "unit_price", "discount", "total_price")
PAYMENT_COLUMNS = ("order_id", "payment_method", "amount", "status", "transaction_id", "provider_response",
                   "paid_at", "created_at")

STATUSES = ("PENDING", "CONFIRMED", "PROCESSING", "SHIPPED", "COMPLETED", "CANCELLED")
STATUS_WEIGHTS = (5, 5, 7, 13, 60, 10)
# Open orders are recent: (max age in days or None = whole history, min age in days)
STATUS_AGE = {
    "PENDING": (10, 0), "CONFIRMED": (20, 0), "PROCESSING": (45, 0.5),
    "SHIPPED": (90, 1), "COMPLETED": (None, 3), "CANCELLED": (None, 0),
}
# How long after created_at the order reached its current status (-> updated_at)
STATUS_UPDATE_DELAY_HOURS = {
    "PENDING": (0, 0), "CONFIRMED": (0.1, 6), "PROCESSING": (6, 48),
    "SHIPPED": (24, 96), "COMPLETED": (72, 240), "CANCELLED": (0.5, 72),
}
METHODS = ("CREDIT_CARD", "DEBIT_CARD", "E_WALLET", "BANK_TRANSFER", "COD", "PAYPAL")
METHOD_WEIGHTS = (38, 12, 20, 10, 14, 6)
COUPON_PERCENT = {"WELCOME10": 10, "SAVE15": 15, "FREESHIP": 0, "BLACKFRIDAY25": 25, "VIP20": 20, "SUMMER10": 10}
ORDER_NOTES = ("Please leave the package at the front door.", "Gift wrap, please.", "Call before delivery.",
               "Deliver after 6pm.", "Fragile - handle with care.", "No plastic packaging please.")
FAIL_CODES = ("card_declined", "insufficient_funds", "expired_card", "processing_error", "timeout")


@dataclass
class Purchases:
    """(user, product, order, time) of COMPLETED order lines that will get a verified
    review. Parallel arrays: millions of entries at ~32 bytes each."""
    user_id: array
    product_id: array
    order_id: array
    ordered_ts: array           # orders.created_at as a POSIX timestamp

    @classmethod
    def empty(cls) -> "Purchases":
        return cls(array("q"), array("q"), array("q"), array("d"))

    def __len__(self) -> int:
        return len(self.order_id)

    def append(self, user_id: int, product_id: int, order_id: int, ordered_ts: float) -> None:
        self.user_id.append(user_id)
        self.product_id.append(product_id)
        self.order_id.append(order_id)
        self.ordered_ts.append(ordered_ts)


# Shipping snapshot = the user's default address at checkout time, read back from
# `addresses` for the users of one batch (served by ux_addresses_one_default_per_user).
DEFAULT_ADDRESS_SQL = """
SELECT user_id, country_code,
       jsonb_build_object('recipient_name', recipient_name, 'phone', phone, 'line1', line1, 'line2', line2,
                          'city', city, 'state', state, 'postal_code', postal_code,
                          'country_code', country_code)::text
FROM addresses
WHERE is_default AND user_id = ANY(%s)
"""


def _default_addresses(ctx: Context, user_ids) -> dict[int, tuple[str, str]]:
    with ctx.conn.cursor() as cur:
        cur.execute(DEFAULT_ADDRESS_SQL, (list(set(user_ids)),))
        return {uid: (country, snapshot) for uid, country, snapshot in cur}


def _order_headers(ctx: Context, users: UserData):
    """Pass 1: pick buyer, status and timestamp for every order."""
    cfg, rng, now = ctx.cfg, ctx.rng, ctx.now
    n = cfg.num_orders
    status_sampler = WeightedSampler(range(len(STATUSES)), STATUS_WEIGHTS)
    history_start = now - timedelta(days=cfg.history_days)

    ts = array("d", bytes(8 * n))
    uid = array("q", bytes(8 * n))
    st = bytearray(n)
    for i in range(n):
        user_id = users.pick_buyer(ctx)
        s = status_sampler.sample(rng)
        max_age, min_age = STATUS_AGE[STATUSES[s]]
        user_created = from_us(users.created_us[user_id - 1])
        lo = max(user_created, history_start if max_age is None else now - timedelta(days=max_age))
        hi = now - timedelta(days=min_age)
        if lo >= hi:                    # brand-new user: can only have a fresh, open order
            s, lo, hi = 0, user_created, now
        created = None
        if max_age is None and rng.random() < 0.10:
            created = holiday_season_between(rng, lo, hi)   # Black Friday -> Christmas peak
        if created is None:
            created = skewed_between(rng, lo, hi, recency=0.7)
        # realistic hour of day; keep the original instant if that would leave [lo, hi]
        with_hour = random_time_of_day(rng, created, ctx.hour_sampler)
        if lo <= with_hour <= hi:
            created = with_hour
        ts[i], uid[i], st[i] = created.timestamp(), user_id, s
    return ts, uid, st


def _provider_response(rng, method: str, status: str, when: datetime) -> str | None:
    if method == "COD":
        resp = {"courier": rng.choice(("UPS", "FedEx", "DHL", "GHN", "J&T"))} if status != "PENDING" else None
    elif method in ("CREDIT_CARD", "DEBIT_CARD"):
        resp = {"provider": "stripe", "card_brand": rng.choice(("visa", "visa", "mastercard", "amex", "jcb")),
                "last4": f"{rng.randint(0, 9999):04d}", "three_ds": rng.random() < 0.6}
    elif method == "E_WALLET":
        resp = {"provider": rng.choice(("apple_pay", "google_pay", "momo", "zalopay", "grabpay"))}
    elif method == "PAYPAL":
        resp = {"provider": "paypal", "payer_status": rng.choice(("verified", "unverified"))}
    else:
        resp = {"bank": rng.choice(("Chase", "Bank of America", "Wells Fargo", "HSBC", "Vietcombank")),
                "reference": f"BT{rng.randint(10**9, 10**10 - 1)}"}
    if resp is None:
        return None
    if status == "FAILED":
        resp["error_code"] = rng.choice(FAIL_CODES)
    elif status == "REFUNDED":
        resp["refund"] = {"reason": rng.choice(("customer_request", "out_of_stock", "fraud_suspected")),
                          "refunded_at": (when + timedelta(days=rng.uniform(0.1, 5))).isoformat()}
    return json.dumps(resp, separators=(",", ":"))


def generate_orders(ctx: Context, users: UserData, products: ProductData) -> Purchases:
    cfg, rng, now = ctx.cfg, ctx.rng, ctx.now
    n = cfg.num_orders
    purchases = Purchases.empty()
    if n == 0:
        return purchases

    print("Generating orders (planning timestamps / buyers / statuses)...", flush=True)
    ts, uid, st = _order_headers(ctx, users)
    order = array("q", sorted(range(n), key=ts.__getitem__))

    method_sampler = WeightedSampler(METHODS, METHOD_WEIGHTS)
    coupon_sampler = WeightedSampler(COUPONS, COUPON_WEIGHTS)
    qty_sampler = WeightedSampler((1, 2, 3, 4, 5), (70, 18, 7, 3, 2))
    extra_items_mean = max(0.0, cfg.avg_items_per_order - 1)
    price_cents = products.price_cents
    pick_product = products.popularity.sample

    # Purchases later turned into verified reviews (~75% of reviews)
    max_purchases = int(cfg.num_reviews * 0.75)
    expected_completed_items = cfg.num_order_items * STATUS_WEIGHTS[4] / sum(STATUS_WEIGHTS)
    review_prob = min(1.0, 1.3 * max_purchases / max(1.0, expected_completed_items))

    progress = Progress("Orders", n)
    items_total = payments_total = 0
    for start, end in ctx.batches(n):
        order_rows, item_rows, payment_rows = [], [], []
        addresses = _default_addresses(ctx, (uid[order[pos]] for pos in range(start, end)))
        for pos in range(start, end):
            i = order[pos]
            order_id = pos + 1
            user_id = uid[i]
            status = STATUSES[st[i]]
            created = datetime.fromtimestamp(ts[i], UTC)

            # ---- items
            n_items = min(1 + poisson(rng, extra_items_mean), 10)
            chosen: set[int] = set()
            for _ in range(n_items * 3):
                if len(chosen) == n_items:
                    break
                chosen.add(pick_product(rng))
            subtotal = 0
            for product_id in chosen:
                qty = qty_sampler.sample(rng)
                unit = price_cents[product_id - 1]
                gross = qty * unit
                line_discount = int(gross * rng.choice((0.05, 0.1, 0.15, 0.2))) if rng.random() < 0.12 else 0
                line_total = gross - line_discount
                subtotal += line_total
                item_rows.append((order_id, product_id, qty, cents_to_str(unit), cents_to_str(line_discount),
                                  cents_to_str(line_total)))
                if status == "COMPLETED" and len(purchases) < max_purchases and rng.random() < review_prob:
                    purchases.append(user_id, product_id, order_id, ts[i])

            # ---- money
            coupon = None
            discount = 0
            if rng.random() < 0.12:
                coupon = coupon_sampler.sample(rng)
                if coupon == "BLACKFRIDAY25" and created.month not in (11, 12):
                    coupon = "SAVE15"
                discount = min(subtotal * COUPON_PERCENT[coupon] // 100, 10_000)
            country, shipping_snapshot = addresses[user_id]
            if coupon == "FREESHIP" or subtotal >= 5_000:
                shipping = 0
            elif country != "US":
                shipping = 1_999
            else:
                shipping = rng.choice((499, 799))
            total = subtotal - discount + shipping

            updated = min(created + timedelta(hours=rng.uniform(*STATUS_UPDATE_DELAY_HOURS[status])), now)

            order_rows.append((
                order_id, user_id, f"ORD-{created:%y%m%d}-{order_id:08d}", status,
                cents_to_str(subtotal), cents_to_str(discount), cents_to_str(shipping), cents_to_str(total),
                "USD", coupon, shipping_snapshot,
                rng.choice(ORDER_NOTES) if rng.random() < 0.04 else None, created, updated,
            ))

            # ---- payments (a few orders have a failed attempt before the final one)
            method = method_sampler.sample(rng)
            if method != "COD" and rng.random() < 0.03:
                failed_method = rng.choice(("CREDIT_CARD", "DEBIT_CARD", "E_WALLET"))
                attempt_at = created + timedelta(seconds=rng.uniform(5, 120))
                payment_rows.append((order_id, failed_method, cents_to_str(total), "FAILED", ctx.uuid4(),
                                     _provider_response(rng, failed_method, "FAILED", attempt_at), None, attempt_at))
            if status == "PENDING" or (method == "COD" and status in ("CONFIRMED", "PROCESSING", "SHIPPED")):
                pay_status = "PENDING"
            elif status == "CANCELLED":
                pay_status = "FAILED" if (method == "COD" or rng.random() < 0.4) else "REFUNDED"
            else:
                pay_status = "SUCCEEDED"
            pay_created = min(created + timedelta(seconds=rng.uniform(130, 600)), now)
            paid_at = None
            if pay_status in ("SUCCEEDED", "REFUNDED"):
                # COD is collected on delivery; online payments are captured within seconds
                paid_at = updated if method == "COD" else pay_created + timedelta(seconds=rng.uniform(1, 90))
                paid_at = min(max(paid_at, pay_created), now)
            payment_rows.append((
                order_id, method, cents_to_str(total), pay_status,
                None if pay_status == "PENDING" else ctx.uuid4(),
                _provider_response(rng, method, pay_status, paid_at or pay_created),
                paid_at, pay_created,
            ))

        copy_rows(ctx.conn, "orders", ORDER_COLUMNS, order_rows)
        copy_rows(ctx.conn, "order_items", ITEM_COLUMNS, item_rows)
        copy_rows(ctx.conn, "payments", PAYMENT_COLUMNS, payment_rows)
        ctx.conn.commit()
        items_total += len(item_rows)
        payments_total += len(payment_rows)
        progress.advance(len(order_rows))

    progress.finish(f"{items_total:,} order_items, {payments_total:,} payments")
    return purchases
