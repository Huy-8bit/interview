-- =============================================================================
-- Secondary indexes
--
-- Indexes that already exist implicitly (PRIMARY KEY / UNIQUE constraints):
--   pk_* on every id, uq_users_username, uq_categories_slug, uq_categories_parent_name,
--   uq_products_sku, uq_warehouses_code, uq_inventory_product_warehouse,
--   uq_orders_order_number, uq_order_items_order_product, uq_payments_transaction_id,
--   uq_reviews_user_product
--
-- This file adds a realistic - NOT exhaustive - set of indexes, one of each kind:
--   B-tree single column, composite, unique, partial, partial unique,
--   expression, GIN (jsonb).
--
-- DELIBERATELY MISSING (practice material for docs/index-lab.md and
-- docs/query-optimization-lab.md):
--   users.email (plain)              -> only lower(email) is indexed
--   users.phone, users.status, users.created_at, users.metadata
--   products.name (use pg_trgm), products.brand, products.status, products.tags
--   orders(user_id, status, created_at), orders.total_amount, orders.coupon_code
--   payments.status, payments.paid_at, payments.payment_method
--   reviews.order_id (unindexed FOREIGN KEY!), reviews.rating, reviews.created_at
--   addresses.city / addresses.country_code
--   inventory.warehouse_id (unindexed FOREIGN KEY)
-- =============================================================================

-- ---- users ------------------------------------------------------------------
-- UNIQUE + EXPRESSION: case-insensitive email uniqueness and lookup.
-- Only helps queries written as  WHERE lower(email) = lower($1)
CREATE UNIQUE INDEX ux_users_email_lower ON users (lower(email));

-- ---- addresses --------------------------------------------------------------
CREATE INDEX idx_addresses_user_id ON addresses (user_id);
-- PARTIAL UNIQUE: at most one default address per user
CREATE UNIQUE INDEX ux_addresses_one_default_per_user ON addresses (user_id) WHERE is_default;

-- ---- categories -------------------------------------------------------------
CREATE INDEX idx_categories_parent_id ON categories (parent_id);

-- ---- products ---------------------------------------------------------------
CREATE INDEX idx_products_category_id ON products (category_id);
CREATE INDEX idx_products_price ON products (price);
-- GIN (jsonb_path_ops): containment queries  attributes @> '{"color": "Black"}'
CREATE INDEX idx_products_attributes_gin ON products USING gin (attributes jsonb_path_ops);

-- ---- orders -----------------------------------------------------------------
CREATE INDEX idx_orders_user_id ON orders (user_id);
CREATE INDEX idx_orders_created_at ON orders (created_at);
-- COMPOSITE: "orders in status X in a date range", ORDER BY created_at
CREATE INDEX idx_orders_status_created_at ON orders (status, created_at);
-- PARTIAL: the operations team only ever looks at open orders (~15% of rows)
CREATE INDEX idx_orders_open_created_at ON orders (created_at)
  WHERE status IN ('PENDING', 'CONFIRMED', 'PROCESSING');

-- ---- order_items ------------------------------------------------------------
-- Intentionally REDUNDANT with uq_order_items_order_product (order_id, product_id):
-- a B-tree on (a, b) already serves lookups on (a). Find & drop it in the index lab.
CREATE INDEX idx_order_items_order_id ON order_items (order_id);
CREATE INDEX idx_order_items_product_id ON order_items (product_id);

-- ---- payments ---------------------------------------------------------------
CREATE INDEX idx_payments_order_id ON payments (order_id);

-- ---- reviews ----------------------------------------------------------------
-- (user_id, ...) lookups are served by uq_reviews_user_product
CREATE INDEX idx_reviews_product_id ON reviews (product_id);

-- ---- inventory --------------------------------------------------------------
-- PARTIAL with an expression predicate: "what needs restocking?"
CREATE INDEX idx_inventory_needs_restock ON inventory (product_id)
  WHERE quantity - reserved_quantity <= reorder_level;
