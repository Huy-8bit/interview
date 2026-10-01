package main

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"time"

	"github.com/jackc/pgx/v5"
)

// Same manifest shape as Python's bulk_ddl.py, so existing recovery tooling can
// recognize it. Only the explicit --bulk-load path creates/drops these objects.
type ddlItem struct {
	Kind  string `json:"kind"`
	Name  string `json:"name"`
	Table string `json:"table"`
	DDL   string `json:"ddl"`
}

const captureDDL = `
SELECT CASE c.contype WHEN 'f' THEN 'fk' ELSE 'unique' END,
       c.conname, t.relname,
       format('ALTER TABLE %s ADD CONSTRAINT %I %s', c.conrelid::regclass, c.conname, pg_get_constraintdef(c.oid))
FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid
WHERE c.contype IN ('f','u') AND t.relnamespace='public'::regnamespace AND t.relname=ANY($1)
UNION ALL
SELECT 'index', idx.relname, t.relname, pg_get_indexdef(i.indexrelid)
FROM pg_index i JOIN pg_class t ON t.oid=i.indrelid JOIN pg_class idx ON idx.oid=i.indexrelid
WHERE t.relnamespace='public'::regnamespace AND t.relname=ANY($1) AND NOT i.indisprimary
AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid=i.indexrelid)`

func (s *databaseSink) deferSchema(ctx context.Context) error {
	rows, err := s.conn.Query(ctx, captureDDL, dataTables)
	if err != nil {
		return err
	}
	var items []ddlItem
	for rows.Next() {
		var item ddlItem
		if err = rows.Scan(&item.Kind, &item.Name, &item.Table, &item.DDL); err != nil {
			rows.Close()
			return err
		}
		items = append(items, item)
	}
	rows.Close()
	if rows.Err() != nil {
		return rows.Err()
	}
	manifest, err := json.Marshal(items)
	if err != nil {
		return err
	}
	// Persist the full manifest before the first DROP, in its own commit.
	if _, err = s.conn.Exec(ctx, "UPDATE data_generator_runs SET deferred_ddl=$1::jsonb WHERE id=$2", string(manifest), s.runID); err != nil {
		return err
	}
	slices.SortStableFunc(items, func(a, b ddlItem) int { return ddlOrder(b.Kind) - ddlOrder(a.Kind) })
	tx, err := s.conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background())
	for _, table := range dataTables {
		if _, err = tx.Exec(ctx, "LOCK TABLE "+pgx.Identifier{"public", table}.Sanitize()+" IN SHARE ROW EXCLUSIVE MODE"); err != nil {
			return err
		}
	}
	if err = requireEmptyData(ctx, tx); err != nil {
		return err
	}
	for _, item := range items {
		stmt := "ALTER TABLE " + pgx.Identifier{"public", item.Table}.Sanitize() + " DROP CONSTRAINT " + pgx.Identifier{item.Name}.Sanitize()
		if item.Kind == "index" {
			stmt = "DROP INDEX " + pgx.Identifier{"public", item.Name}.Sanitize()
		}
		if _, err = tx.Exec(ctx, stmt); err != nil {
			return err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}
	fmt.Printf("Bulk load: deferred %d indexes/constraints; definitions saved in run %d\n", len(items), s.runID)
	return nil
}
func ddlOrder(kind string) int {
	switch kind {
	case "index":
		return 0
	case "unique":
		return 1
	case "fk":
		return 2
	}
	return 3
}
func (s *databaseSink) restoreSchema(ctx context.Context) error {
	var locked bool
	if err := s.conn.QueryRow(ctx, "SELECT pg_try_advisory_lock($1)", generatorLock).Scan(&locked); err != nil {
		return err
	}
	if !locked {
		return fmt.Errorf("another Go generator is running")
	}
	rows, err := s.conn.Query(ctx, `SELECT id,deferred_ddl FROM data_generator_runs WHERE settings->>'Engine'='go' AND deferred_ddl IS NOT NULL ORDER BY id`)
	if err != nil {
		return err
	}
	type pendingRun struct {
		id    int64
		items []ddlItem
	}
	var pending []pendingRun
	for rows.Next() {
		var p pendingRun
		var data []byte
		if err = rows.Scan(&p.id, &data); err != nil {
			rows.Close()
			return err
		}
		if err = json.Unmarshal(data, &p.items); err != nil {
			rows.Close()
			return err
		}
		pending = append(pending, p)
	}
	rows.Close()
	if rows.Err() != nil {
		return rows.Err()
	}
	if len(pending) == 0 {
		return nil
	}
	if _, err = s.conn.Exec(ctx, "SET maintenance_work_mem='256MB'"); err != nil {
		return err
	}
	for _, p := range pending {
		slices.SortStableFunc(p.items, func(a, b ddlItem) int { return ddlOrder(a.Kind) - ddlOrder(b.Kind) })
		for _, item := range p.items {
			var exists bool
			if item.Kind == "index" {
				err = s.conn.QueryRow(ctx, "SELECT to_regclass($1) IS NOT NULL", pgx.Identifier{"public", item.Name}.Sanitize()).Scan(&exists)
			} else {
				err = s.conn.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname=$1 AND conrelid=$2::regclass)", item.Name, pgx.Identifier{"public", item.Table}.Sanitize()).Scan(&exists)
			}
			if err != nil {
				return err
			}
			if exists {
				continue
			}
			started := time.Now()
			if _, err = s.conn.Exec(ctx, item.DDL); err != nil {
				return fmt.Errorf("restore %s: %w; retry with --restore-schema", item.Name, err)
			}
			fmt.Printf("  restored %-42s %.2fs\n", item.Name, time.Since(started).Seconds())
		}
		if _, err = s.conn.Exec(ctx, "UPDATE data_generator_runs SET deferred_ddl=NULL WHERE id=$1", p.id); err != nil {
			return err
		}
		if p.id != s.runID {
			if _, err = s.conn.Exec(ctx, "UPDATE data_generator_runs SET status='FAILED',error=coalesce(error,'Interrupted bulk load; schema restored, partial rows preserved'),finished_at=coalesce(finished_at,now()) WHERE id=$1 AND status='RUNNING'", p.id); err != nil {
				return err
			}
		}
	}
	return nil
}
