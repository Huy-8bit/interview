-- =============================================================================
-- Data quality report for the generated e-commerce dataset.
--   ./scripts/verify-data.sh            (runs this on the REPLICA: read-only, and it
--                                         proves the data replicated as well)
-- Every check returns bad_rows = 0 when the data is consistent. A non-zero value
-- prints FAIL and makes verify-data.sh exit 1.
-- Takes ~1 min on the 5M profile (it aggregates every order line).
-- =============================================================================
\pset pager off
\timing off
SET max_parallel_workers_per_gather = 4;
SET work_mem = '64MB';

\echo
\echo '== Row counts (planner estimate from the last ANALYZE; pg_stat_* counters are per node and empty on a replica) =='
SELECT relname AS table_name, to_char(reltuples, 'FM999,999,999') AS approx_rows,
       pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_class
WHERE relnamespace = 'public'::regnamespace AND relkind = 'r'
  AND relname NOT IN ('data_generator_runs', 'replication_test')
ORDER BY reltuples DESC;

\echo
\echo '== Referential + business consistency (bad_rows must be 0) =='
WITH checks(check_name, bad_rows) AS (
  -- FOREIGN KEY constraints exist and are validated -> no orphan rows anywhere
  SELECT 'foreign keys not validated', count(*) FROM pg_constraint
  WHERE contype = 'f' AND connamespace = 'public'::regnamespace AND NOT convalidated
  UNION ALL
  SELECT 'users without exactly one default address', count(*) FROM (
    SELECT u.id FROM users u LEFT JOIN addresses a ON a.user_id = u.id AND a.is_default
    GROUP BY u.id HAVING count(a.id) <> 1) s
  UNION ALL
  SELECT 'orders without order_items', count(*) FROM orders o
  WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.id)
  UNION ALL
  SELECT 'orders.subtotal <> sum(order_items.total_price)', count(*) FROM orders o
  JOIN (SELECT order_id, sum(total_price) AS s FROM order_items GROUP BY order_id) i ON i.order_id = o.id
  WHERE o.subtotal <> i.s
  UNION ALL
  SELECT 'orders without payment', count(*) FROM orders o
  WHERE NOT EXISTS (SELECT 1 FROM payments p WHERE p.order_id = o.id)
  UNION ALL
  SELECT 'payments.amount <> orders.total_amount', count(*) FROM payments p
  JOIN orders o ON o.id = p.order_id WHERE p.amount <> o.total_amount
  UNION ALL
  SELECT 'COMPLETED orders without a SUCCEEDED payment', count(*) FROM orders o
  WHERE o.status = 'COMPLETED'
    AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.order_id = o.id AND p.status = 'SUCCEEDED')
  UNION ALL
  SELECT 'shipping snapshot country <> default address country', count(*) FROM orders o
  JOIN addresses a ON a.user_id = o.user_id AND a.is_default
  WHERE o.shipping_address ->> 'country_code' <> a.country_code
  UNION ALL
  SELECT 'products.stock_quantity <> sum(inventory.quantity)', count(*) FROM products p
  LEFT JOIN (SELECT product_id, sum(quantity) AS q FROM inventory GROUP BY product_id) inv ON inv.product_id = p.id
  WHERE p.stock_quantity <> coalesce(inv.q, 0)
  UNION ALL
  SELECT 'DRAFT products that were sold', count(*) FROM products p
  WHERE p.status = 'DRAFT' AND EXISTS (SELECT 1 FROM order_items i WHERE i.product_id = p.id)
  UNION ALL
  -- a verified review must point to a COMPLETED order of the SAME user that CONTAINS the product
  SELECT 'verified reviews not backed by a matching completed purchase', count(*) FROM reviews r
  WHERE r.is_verified_purchase AND NOT EXISTS (
    SELECT 1 FROM orders o JOIN order_items i ON i.order_id = o.id
    WHERE o.id = r.order_id AND o.user_id = r.user_id AND o.status = 'COMPLETED' AND i.product_id = r.product_id)
  UNION ALL
  -- temporal consistency
  SELECT 'orders placed before the user signed up', count(*) FROM orders o
  JOIN users u ON u.id = o.user_id WHERE o.created_at < u.created_at
  UNION ALL
  SELECT 'order lines for a product not yet created', count(*) FROM order_items i
  JOIN orders o ON o.id = i.order_id JOIN products p ON p.id = i.product_id WHERE o.created_at < p.created_at
  UNION ALL
  SELECT 'payments created before their order', count(*) FROM payments p
  JOIN orders o ON o.id = p.order_id WHERE p.created_at < o.created_at
  UNION ALL
  SELECT 'reviews written before the product existed', count(*) FROM reviews r
  JOIN products p ON p.id = r.product_id WHERE r.created_at < p.created_at
  UNION ALL
  SELECT 'reviews written before the user signed up', count(*) FROM reviews r
  JOIN users u ON u.id = r.user_id WHERE r.created_at < u.created_at
  UNION ALL
  SELECT 'verified reviews written before the order', count(*) FROM reviews r
  JOIN orders o ON o.id = r.order_id WHERE r.created_at < o.created_at
)
SELECT check_name, bad_rows, CASE WHEN bad_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks;

\echo
\echo '== Distributions (skewed on purpose: see README "Dữ liệu") =='
SELECT status, to_char(count(*), 'FM999,999,999') AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM orders GROUP BY status ORDER BY count(*) DESC;

WITH per_user AS (SELECT user_id, count(*) AS n FROM orders GROUP BY user_id),
     ranked AS (SELECT n, ntile(5) OVER (ORDER BY n DESC) AS quintile FROM per_user)
SELECT quintile AS buyer_quintile, round(100.0 * sum(n) / (SELECT count(*) FROM orders), 1) AS pct_of_orders
FROM ranked GROUP BY quintile ORDER BY quintile;

WITH per_product AS (SELECT product_id, sum(quantity) AS units FROM order_items GROUP BY product_id),
     ranked AS (SELECT units, ntile(100) OVER (ORDER BY units DESC) AS pctile FROM per_product)
SELECT round(100.0 * sum(units) FILTER (WHERE pctile = 1) / sum(units), 1) AS top_1pct_products_pct_of_units,
       (SELECT count(*) FROM products) - count(*)                         AS products_never_sold,
       (SELECT count(*) FROM users u WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id)) AS users_never_ordered
FROM ranked;

\echo
\echo '== Relational queries return real data =='
\echo '-- top 5 customers: orders -> items -> products -> reviews'
SELECT u.id AS user_id, u.username,
       count(DISTINCT o.id)          AS orders,
       count(i.id)                   AS order_lines,
       count(DISTINCT i.product_id)  AS distinct_products,
       sum(i.total_price)            AS spent,
       (SELECT count(*) FROM reviews r WHERE r.user_id = u.id) AS reviews_written
FROM users u
JOIN orders o      ON o.user_id = u.id AND o.status = 'COMPLETED'
JOIN order_items i ON i.order_id = o.id
WHERE u.id IN (SELECT user_id FROM orders GROUP BY user_id ORDER BY count(*) DESC LIMIT 5)
GROUP BY u.id, u.username
ORDER BY orders DESC;

\echo '-- top 5 products: category path, units sold, buyers, rating'
WITH best AS (
  SELECT product_id, sum(quantity) AS units, count(DISTINCT o.user_id) AS buyers
  FROM order_items i JOIN orders o ON o.id = i.order_id
  GROUP BY product_id ORDER BY units DESC LIMIT 5
)
SELECT p.id, left(p.name, 40) AS product, parent.name || ' > ' || c.name AS category,
       b.units, b.buyers,
       round(avg(r.rating), 2) AS avg_rating,
       count(r.id) FILTER (WHERE r.is_verified_purchase) AS verified_reviews
FROM best b
JOIN products p        ON p.id = b.product_id
JOIN categories c      ON c.id = p.category_id
JOIN categories parent ON parent.id = c.parent_id
LEFT JOIN reviews r    ON r.product_id = p.id
GROUP BY p.id, p.name, parent.name, c.name, b.units, b.buyers
ORDER BY b.units DESC;

\echo '-- one customer journey: order -> lines -> payment -> review of what was bought'
WITH u AS (
  SELECT r.user_id FROM reviews r WHERE r.is_verified_purchase ORDER BY r.helpful_count DESC, r.id LIMIT 1
)
SELECT o.order_number, o.status AS order_status, o.created_at::date AS ordered,
       left(p.name, 35) AS product, i.quantity, i.total_price,
       (SELECT string_agg(pm.payment_method || ':' || pm.status, ', ' ORDER BY pm.id)
          FROM payments pm WHERE pm.order_id = o.id) AS payments,
       r.rating, r.created_at::date AS reviewed
FROM u
JOIN orders o      ON o.user_id = u.user_id
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
LEFT JOIN reviews r ON r.order_id = o.id AND r.product_id = i.product_id
ORDER BY o.created_at, p.name
LIMIT 15;
