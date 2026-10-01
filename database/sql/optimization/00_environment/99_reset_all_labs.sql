-- =============================================================================
-- 00_environment / 99 · Emergency reset: remove EVERYTHING any lab may have left
--
-- Normal workflow: run the lab's own 05_reset.sql. Use this file when you lost
-- track (e.g. ran several labs without resetting). It only touches objects that
-- follow the lab naming convention, so the baseline schema and data are safe:
--   ix_lab*   indexes            st_lab*  extended statistics
--   lab_*     tables (+ their partitions, indexes)
--   mv_lab*   materialized views
-- plus per-column statistics targets, storage parameters and session settings.
-- =============================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT matviewname FROM pg_matviews WHERE schemaname = 'public' AND matviewname LIKE 'mv\_lab%' LOOP
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE', r.matviewname);
    RAISE NOTICE 'dropped materialized view %', r.matviewname;
  END LOOP;

  FOR r IN SELECT c.relname FROM pg_class c
           WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p')
             AND c.relname LIKE 'lab\_%' AND NOT c.relispartition LOOP
    EXECUTE format('DROP TABLE IF EXISTS %I CASCADE', r.relname);
    RAISE NOTICE 'dropped table %', r.relname;
  END LOOP;

  FOR r IN SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND indexname LIKE 'ix\_lab%' LOOP
    EXECUTE format('DROP INDEX IF EXISTS %I', r.indexname);
    RAISE NOTICE 'dropped index %', r.indexname;
  END LOOP;

  FOR r IN SELECT stxname FROM pg_statistic_ext WHERE stxnamespace = 'public'::regnamespace AND stxname LIKE 'st\_lab%' LOOP
    EXECUTE format('DROP STATISTICS IF EXISTS %I', r.stxname);
    RAISE NOTICE 'dropped statistics %', r.stxname;
  END LOOP;

  FOR r IN SELECT a.attrelid::regclass AS tbl, a.attname
           FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
           WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
             AND a.attnum > 0 AND NOT a.attisdropped AND a.attstattarget <> -1 LOOP
    EXECUTE format('ALTER TABLE %s ALTER COLUMN %I SET STATISTICS -1', r.tbl, r.attname);
    RAISE NOTICE 'reset statistics target of %.%', r.tbl, r.attname;
  END LOOP;

  FOR r IN SELECT a.attrelid::regclass AS tbl, a.attname, a.attoptions
           FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
           WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
             AND a.attnum > 0 AND NOT a.attisdropped AND a.attoptions IS NOT NULL LOOP
    EXECUTE format('ALTER TABLE %s ALTER COLUMN %I RESET (%s)', r.tbl, r.attname,
                   (SELECT string_agg(split_part(o, '=', 1), ', ') FROM unnest(r.attoptions) o));
    RAISE NOTICE 'reset column options of %.%', r.tbl, r.attname;
  END LOOP;

  FOR r IN SELECT c.oid::regclass AS rel, c.relkind, c.reloptions
           FROM pg_class c
           WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'i') AND c.reloptions IS NOT NULL LOOP
    EXECUTE format('ALTER %s %s RESET (%s)', CASE r.relkind WHEN 'i' THEN 'INDEX' ELSE 'TABLE' END, r.rel,
                   (SELECT string_agg(split_part(o, '=', 1), ', ') FROM unnest(r.reloptions) o));
    RAISE NOTICE 'reset storage parameters of %', r.rel;
  END LOOP;
END $$;

-- Session settings changed by the labs (SET work_mem, enable_*, ...)
RESET ALL;

-- Statistics may have been modified by the labs (lab 32 / 35): refresh the main tables
ANALYZE users;
ANALYZE addresses;
ANALYZE products;
ANALYZE orders;
ANALYZE order_items;
ANALYZE payments;
ANALYZE reviews;

-- Must return "BASELINE OK" (same check as 09_verify_baseline.sql)
SELECT count(*) FILTER (WHERE indexname LIKE 'ix\_lab%') AS lab_indexes_left,
       (SELECT count(*) FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relname LIKE 'lab\_%') AS lab_tables_left,
       (SELECT count(*) FROM pg_statistic_ext WHERE stxnamespace = 'public'::regnamespace) AS statistics_objects_left
FROM pg_indexes WHERE schemaname = 'public';
