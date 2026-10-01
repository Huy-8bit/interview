"""Reference data: categories (2-level tree) and warehouses."""

from __future__ import annotations

from dataclasses import dataclass

from .context import Context, ascii_slug
from .db import copy_rows
from .distributions import WeightedSampler, days_ago
from .reference import CATEGORY_TREE, WAREHOUSES, Leaf, TopCategory


@dataclass(frozen=True)
class LeafCategory:
    id: int
    leaf: Leaf
    top: TopCategory


@dataclass
class Catalog:
    leaves: list[LeafCategory]
    leaf_sampler: WeightedSampler[LeafCategory]
    warehouse_ids: list[int]


def generate_catalog(ctx: Context) -> Catalog:
    print("Generating categories...", flush=True)
    rows, leaves = [], []
    created = days_ago(ctx.now, ctx.cfg.history_days + 400)
    next_id = 1
    for top_order, top in enumerate(CATEGORY_TREE, start=1):
        top_id = next_id
        next_id += 1
        rows.append((top_id, None, top.name, ascii_slug(top.name, "-"),
                     f"All {top.name.lower()} products", True, top_order, created))
        for leaf_order, leaf in enumerate(top.leaves, start=1):
            leaf_id = next_id
            next_id += 1
            rows.append((leaf_id, top_id, leaf.name, f"{ascii_slug(top.name, '-')}-{ascii_slug(leaf.name, '-')}",
                         f"{leaf.name} in {top.name}", True, leaf_order, created))
            leaves.append(LeafCategory(leaf_id, leaf, top))

    copy_rows(ctx.conn, "categories",
              ("id", "parent_id", "name", "slug", "description", "is_active", "sort_order", "created_at"), rows)
    print(f"  Categories: {len(rows)} / {len(rows)}", flush=True)

    print("Generating warehouses...", flush=True)
    wh_rows = [(i, code, name, city, country, True, created)
               for i, (code, name, city, country) in enumerate(WAREHOUSES, start=1)]
    copy_rows(ctx.conn, "warehouses",
              ("id", "code", "name", "city", "country_code", "is_active", "created_at"), wh_rows)
    print(f"  Warehouses: {len(wh_rows)} / {len(wh_rows)}", flush=True)
    ctx.conn.commit()

    return Catalog(
        leaves=leaves,
        leaf_sampler=WeightedSampler(leaves, [lc.leaf.weight for lc in leaves]),
        warehouse_ids=[r[0] for r in wh_rows],
    )
