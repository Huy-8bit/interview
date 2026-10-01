-- =============================================================================
-- 00_environment / 09 · Is the database back at its BASELINE state?
--
-- Run after any lab's 05_reset.sql. Returns ONE row "BASELINE OK" when nothing
-- created or changed by a lab is left; otherwise one row per leftover.
-- Baseline = schema from postgres/primary/init/*.sql (36 indexes, constraints,
-- default statistics targets, no reloptions, all triggers enabled, no lab objects).
-- scripts/test-optimization-labs.sh runs this after every lab.
-- =============================================================================

WITH baseline_index(table_name, index_name) AS (
  VALUES
    ('addresses', 'idx_addresses_user_id'), ('addresses', 'pk_addresses'), ('addresses', 'ux_addresses_one_default_per_user'),
    ('categories', 'idx_categories_parent_id'), ('categories', 'pk_categories'),
    ('categories', 'uq_categories_parent_name'), ('categories', 'uq_categories_slug'),
    ('data_generator_runs', 'data_generator_runs_pkey'),
    ('inventory', 'idx_inventory_needs_restock'), ('inventory', 'pk_inventory'), ('inventory', 'uq_inventory_product_warehouse'),
    ('order_items', 'idx_order_items_order_id'), ('order_items', 'idx_order_items_product_id'),
    ('order_items', 'pk_order_items'), ('order_items', 'uq_order_items_order_product'),
    ('orders', 'idx_orders_created_at'), ('orders', 'idx_orders_open_created_at'), ('orders', 'idx_orders_status_created_at'),
    ('orders', 'idx_orders_user_id'), ('orders', 'pk_orders'), ('orders', 'uq_orders_order_number'),
    ('payments', 'idx_payments_order_id'), ('payments', 'pk_payments'), ('payments', 'uq_payments_transaction_id'),
    ('products', 'idx_products_attributes_gin'), ('products', 'idx_products_category_id'), ('products', 'idx_products_price'),
    ('products', 'pk_products'), ('products', 'uq_products_sku'),
    ('replication_test', 'replication_test_pkey'), ('replication_test', 'replication_test_token_key'),
    ('reviews', 'idx_reviews_product_id'), ('reviews', 'pk_reviews'), ('reviews', 'uq_reviews_user_product'),
    ('users', 'pk_users'), ('users', 'uq_users_username'), ('users', 'ux_users_email_lower'),
    ('warehouses', 'pk_warehouses'), ('warehouses', 'uq_warehouses_code')
),
baseline_table(table_name) AS (
  VALUES ('addresses'), ('categories'), ('data_generator_runs'), ('inventory'), ('order_items'), ('orders'),
         ('payments'), ('products'), ('replication_test'), ('reviews'), ('users'), ('warehouses')
),
current_index AS (
  SELECT tablename AS table_name, indexname AS index_name FROM pg_indexes WHERE schemaname = 'public'
),
problems(kind, object, detail) AS (
  SELECT 'LEFTOVER index', c.table_name || '.' || c.index_name,
         'DROP INDEX IF EXISTS ' || quote_ident(c.index_name) || ';'
  FROM current_index c
  WHERE NOT EXISTS (SELECT 1 FROM baseline_index b WHERE b.table_name = c.table_name AND b.index_name = c.index_name)
    AND c.table_name IN (SELECT table_name FROM baseline_table)
  UNION ALL
  SELECT 'MISSING baseline index', b.table_name || '.' || b.index_name,
         'see postgres/primary/init/04-indexes.sql (or a crashed data-generator: rerun it)'
  FROM baseline_index b
  WHERE NOT EXISTS (SELECT 1 FROM current_index c WHERE c.table_name = b.table_name AND c.index_name = b.index_name)
  UNION ALL
  SELECT 'INVALID index', indexrelid::regclass::text, 'failed CREATE INDEX CONCURRENTLY: drop it'
  FROM pg_index WHERE NOT indisvalid
  UNION ALL
  SELECT 'LEFTOVER table/view', c.relname || ' (' || c.relkind::text || ')',
         'DROP ' || CASE c.relkind WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'v' THEN 'VIEW' ELSE 'TABLE' END
         || ' IF EXISTS ' || quote_ident(c.relname) || ' CASCADE;'
  FROM pg_class c
  WHERE c.relnamespace = 'public'::regnamespace
    AND c.relkind IN ('r', 'p', 'm', 'v')
    AND c.relname NOT IN (SELECT table_name FROM baseline_table)
    AND NOT c.relispartition
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = c.oid AND d.deptype = 'e')   -- extension views
  UNION ALL
  SELECT 'LEFTOVER statistics object', stxname, 'DROP STATISTICS IF EXISTS ' || quote_ident(stxname) || ';'
  FROM pg_statistic_ext WHERE stxnamespace = 'public'::regnamespace
  UNION ALL
  SELECT 'CHANGED statistics target', a.attrelid::regclass || '.' || a.attname,
         format('ALTER TABLE %s ALTER COLUMN %I SET STATISTICS -1;', a.attrelid::regclass, a.attname)
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
    AND a.attnum > 0 AND NOT a.attisdropped AND a.attstattarget <> -1
  UNION ALL
  SELECT 'CHANGED column option', a.attrelid::regclass || '.' || a.attname,
         format('ALTER TABLE %s ALTER COLUMN %I RESET (%s);', a.attrelid::regclass, a.attname,
                (SELECT string_agg(split_part(o, '=', 1), ', ') FROM unnest(a.attoptions) o))
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
    AND a.attnum > 0 AND NOT a.attisdropped AND a.attoptions IS NOT NULL
  UNION ALL
  SELECT 'CHANGED storage parameters', c.relname, array_to_string(c.reloptions, ', ')
  FROM pg_class c
  WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'i') AND c.reloptions IS NOT NULL
  UNION ALL
  SELECT 'DISABLED trigger', tgrelid::regclass || '.' || tgname,
         format('ALTER TABLE %s ENABLE TRIGGER %I;', tgrelid::regclass, tgname)
  FROM pg_trigger
  WHERE NOT tgisinternal AND tgenabled <> 'O' AND tgrelid::regclass::text IN (SELECT table_name FROM baseline_table)
  UNION ALL
  SELECT 'LEFTOVER function', p.oid::regprocedure::text, 'DROP FUNCTION IF EXISTS ' || p.oid::regprocedure || ';'
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname <> 'set_updated_at'
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')   -- extension functions
  UNION ALL
  SELECT 'CHANGED database/role setting', coalesce(r.rolname, '(all roles)'), array_to_string(s.setconfig, ', ')
  FROM pg_db_role_setting s
  LEFT JOIN pg_roles r ON r.oid = s.setrole
  WHERE s.setdatabase IN (0, (SELECT oid FROM pg_database WHERE datname = current_database()))
  UNION ALL
  SELECT 'CHANGED session setting', name, setting || '  (RESET ' || name || ';)'
  FROM pg_settings WHERE source = 'session' AND name NOT IN ('application_name', 'client_encoding', 'DateStyle')
)
SELECT kind, object, detail FROM problems
UNION ALL
SELECT 'BASELINE OK', '-', 'no lab objects or setting changes left'
WHERE NOT EXISTS (SELECT 1 FROM problems)
ORDER BY 1, 2;
