"""users + addresses."""

from __future__ import annotations

import json
from array import array
from dataclasses import dataclass
from datetime import date, timedelta

from .context import Context, ascii_slug
from .db import Progress, copy_rows
from .distributions import WeightedSampler, days_ago, skewed_between, to_us
from .reference import (EMAIL_DOMAIN_WEIGHTS, EMAIL_DOMAINS, INTERNATIONAL_CITIES, INTERNATIONAL_SHARE,
                        LANGUAGE_WEIGHTS, LANGUAGES, SIGNUP_SOURCE_WEIGHTS, SIGNUP_SOURCES, US_TOP_CITIES)

USER_COLUMNS = ("id", "username", "email", "password_hash", "full_name", "phone", "date_of_birth", "gender",
                "status", "is_email_verified", "loyalty_points", "last_login_at", "last_login_ip", "metadata",
                "created_at", "updated_at")
ADDRESS_COLUMNS = ("user_id", "label", "recipient_name", "phone", "line1", "line2", "city", "state",
                   "postal_code", "country_code", "is_default", "created_at")

PHONE_PREFIX = {"US": "+1", "CA": "+1", "GB": "+44", "DE": "+49", "FR": "+33", "AU": "+61",
                "JP": "+81", "SG": "+65", "VN": "+84"}
BCRYPT_ALPHABET = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"


@dataclass
class UserData:
    # Compact arrays only (millions of users): orders look up the default address
    # (shipping snapshot + country) in the database batch by batch instead.
    created_us: array                   # signup time in epoch microseconds, index = user_id - 1
    heavy_ids: array                    # the ~20% of users that place ~70% of orders
    light_ids: array
    heavy_flags: bytearray

    def pick_buyer(self, ctx: Context) -> int:
        rng = ctx.rng
        pool = self.heavy_ids if (rng.random() < ctx.cfg.heavy_user_order_share or not self.light_ids) else self.light_ids
        return pool[rng.randrange(len(pool))]


class _Geo:
    """Samples (country, city, state, postal_code) with a realistic skew."""

    def __init__(self, ctx: Context):
        fake = ctx.fake
        self.rng = ctx.rng
        self.us_top = WeightedSampler(US_TOP_CITIES, [w for *_, w in US_TOP_CITIES])
        self.intl = WeightedSampler(INTERNATIONAL_CITIES, [w for *_, w in INTERNATIONAL_CITIES])
        # Long tail of small (fake) US towns: each appears only a handful of times
        self.us_tail = [(fake.city(), fake.state_abbr()) for _ in range(3000)]
        self.streets = [fake.street_name() for _ in range(5000)]

    def pick(self) -> tuple[str, str, str | None, str]:
        rng = self.rng
        if rng.random() < INTERNATIONAL_SHARE:
            country, city, state, _ = self.intl.sample(rng)
            return country, city, state, f"{rng.randint(10000, 99999)}"
        if rng.random() < 0.7:
            city, state, _ = self.us_top.sample(rng)
        else:
            city, state = self.us_tail[rng.randrange(len(self.us_tail))]
        return "US", city, state, f"{rng.randint(1000, 99999):05d}"

    def street(self) -> str:
        return f"{self.rng.randint(1, 9999)} {self.streets[self.rng.randrange(len(self.streets))]}"


def _phone(rng, country: str) -> str:
    prefix = PHONE_PREFIX.get(country, "+1")
    if prefix == "+1":
        return f"+1-{rng.randint(201, 989)}-{rng.randint(200, 999)}-{rng.randint(0, 9999):04d}"
    return f"{prefix} {rng.randint(10, 99)} {rng.randint(100, 999)} {rng.randint(1000, 9999)}"


def generate_users(ctx: Context) -> UserData:
    cfg, rng, fake, now = ctx.cfg, ctx.rng, ctx.fake, ctx.now
    n = cfg.num_users

    # Signup times sorted ascending so that user id order == signup order
    # (physical order correlates with created_at: see pg_stats.correlation / BRIN lab).
    oldest = days_ago(now, cfg.history_days + 365)
    newest = now - timedelta(hours=1)
    created_at = sorted(skewed_between(rng, oldest, newest, recency=0.6) for _ in range(n))

    heavy_count = max(1, round(n * cfg.heavy_user_share))
    heavy_ids = array("q", sorted(rng.sample(range(1, n + 1), heavy_count)))
    heavy_flags = bytearray(n + 1)
    for uid in heavy_ids:
        heavy_flags[uid] = 1
    light_ids = array("q", (uid for uid in range(1, n + 1) if not heavy_flags[uid]))

    geo = _Geo(ctx)
    domain_sampler = WeightedSampler(EMAIL_DOMAINS, EMAIL_DOMAIN_WEIGHTS)
    source_sampler = WeightedSampler(SIGNUP_SOURCES, SIGNUP_SOURCE_WEIGHTS)
    lang_sampler = WeightedSampler(LANGUAGES, LANGUAGE_WEIGHTS)
    status_sampler = WeightedSampler(("ACTIVE", "INACTIVE", "SUSPENDED", "DELETED"), (90, 6, 1, 3))
    gender_sampler = WeightedSampler(("M", "F", "O", None), (47, 48, 2, 3))
    label_sampler = WeightedSampler(("WORK", "OTHER"), (60, 40))

    users_progress = Progress("Users", n)
    total_addresses = 0
    for start, end in ctx.batches(n):
        user_rows, address_rows = [], []
        for idx in range(start, end):
            uid = idx + 1
            is_heavy = heavy_flags[uid] == 1
            first, last = fake.first_name(), fake.last_name()
            full_name = f"{first} {last}"
            f_slug, l_slug = ascii_slug(first) or "user", ascii_slug(last) or "x"
            username = f"{f_slug}.{l_slug}{uid}"[:50]

            style = rng.random()
            if style < 0.6:
                local = f"{f_slug}.{l_slug}{uid}"
            elif style < 0.8:
                local = f"{f_slug}{l_slug}{uid}"
            else:
                local = f"{f_slug[0]}{l_slug}{uid}"
            email = f"{local}@{domain_sampler.sample(rng)}"
            if rng.random() < 0.05:  # mixed-case emails -> lower(email) lesson
                email = email[0].upper() + email[1:].replace("@g", "@G")

            country, city, state, postal = geo.pick()
            phone = _phone(rng, country) if rng.random() < 0.85 else None
            created = created_at[idx]

            dob = None
            if rng.random() < 0.8:
                age = rng.triangular(18, 75, 31)
                dob = date.fromordinal(now.date().toordinal() - int(age * 365.25))
            last_login = skewed_between(rng, created, now, recency=0.3) if rng.random() < 0.9 else None

            metadata = {
                "signup_source": source_sampler.sample(rng),
                "preferred_language": "vi" if country == "VN" else lang_sampler.sample(rng),
                "marketing_opt_in": rng.random() < 0.45,
                "preferences": {"currency": "USD", "theme": "dark" if rng.random() < 0.35 else "light"},
            }
            if rng.random() < 0.3:
                metadata["newsletter_frequency"] = rng.choice(("daily", "weekly", "monthly"))
            if is_heavy and rng.random() < 0.15:
                metadata["tags"] = ["vip"] + (["wholesale"] if rng.random() < 0.1 else [])
            elif rng.random() < 0.02:
                metadata["tags"] = ["fraud_review"]
            if metadata["signup_source"] == "referral":
                metadata["referred_by"] = rng.randint(1, max(1, uid - 1))

            user_rows.append((
                uid, username, email,
                "$2b$12$" + "".join(rng.choices(BCRYPT_ALPHABET, k=53)),
                full_name, phone, dob, gender_sampler.sample(rng), status_sampler.sample(rng),
                rng.random() < 0.82,
                int(rng.expovariate(1 / 250) * (3 if is_heavy else 1)),
                last_login,
                f"{rng.randint(1, 223)}.{rng.randint(0, 255)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}"
                if last_login else None,
                json.dumps(metadata, separators=(",", ":")),
                created,
                max(created, last_login) if last_login else created,
            ))

            # ---- addresses: 1 (55%), 2 (30%) or 3 (15%); the first is the default
            r = rng.random()
            n_addr = 1 if r < 0.55 else (2 if r < 0.85 else 3)
            for a in range(n_addr):
                if a > 0:
                    country_a, city, state, postal = geo.pick() if rng.random() < 0.3 else (country, city, state, postal)
                else:
                    country_a = country
                recipient = full_name if (a == 0 or rng.random() < 0.8) else fake.name()
                line1 = geo.street()
                line2 = rng.choice((f"Apt {rng.randint(1, 999)}", f"Suite {rng.randint(100, 999)}",
                                    f"Floor {rng.randint(1, 40)}")) if rng.random() < 0.25 else None
                addr_created = created + timedelta(days=rng.random() * 30 * a)
                if addr_created > now:
                    addr_created = now
                address_rows.append((
                    uid, "HOME" if a == 0 else label_sampler.sample(rng), recipient,
                    phone if a == 0 else (_phone(rng, country_a) if rng.random() < 0.7 else None),
                    line1, line2, city, state, postal, country_a, a == 0, addr_created,
                ))

        copy_rows(ctx.conn, "users", USER_COLUMNS, user_rows)
        copy_rows(ctx.conn, "addresses", ADDRESS_COLUMNS, address_rows)
        ctx.conn.commit()
        total_addresses += len(address_rows)
        users_progress.advance(len(user_rows))

    users_progress.finish(f"{total_addresses:,} addresses")
    created_us = array("q", map(to_us, created_at))
    del created_at
    return UserData(created_us, heavy_ids, light_ids, heavy_flags)
