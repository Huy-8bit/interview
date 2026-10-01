package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
)

var dataTables = []string{"categories", "warehouses", "users", "addresses", "products", "inventory", "orders", "order_items", "payments", "reviews"}

const generatorLock int64 = 0x50474c4142474f

type databaseSink struct {
	conn  *pgx.Conn
	runID int64
}

func envDefault(k, fallback string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return fallback
}
func connectionConfig() (*pgx.ConnConfig, error) {
	port, err := strconv.ParseUint(envDefault("DB_PORT", "5432"), 10, 16)
	if err != nil || port == 0 {
		return nil, fmt.Errorf("invalid DB_PORT")
	}
	// Parse the actual target, including fallback/TLS addresses, together. Changing
	// Host/Port after ParseConfig could leave a fallback pointing at localhost:5432.
	u := &url.URL{Scheme: "postgresql", Host: net.JoinHostPort(envDefault("DB_HOST", "localhost"), strconv.Itoa(int(port))),
		User: url.UserPassword(envDefault("DB_USER", "postgres"), envDefault("DB_PASSWORD", "postgres")), Path: "/" + envDefault("DB_NAME", "ecommerce")}
	c, err := pgx.ParseConfig(u.String())
	if err != nil {
		return nil, fmt.Errorf("invalid PostgreSQL connection configuration")
	}
	c.ConnectTimeout = 10 * time.Second
	c.RuntimeParams["application_name"] = "data-generator-go"
	c.RuntimeParams["search_path"] = "public"
	c.RuntimeParams["timezone"] = "UTC"
	c.RuntimeParams["lock_timeout"] = "5s"
	return c, nil
}

func openDB(ctx context.Context) (*databaseSink, error) {
	c, err := connectionConfig()
	if err != nil {
		return nil, err
	}
	conn, err := pgx.ConnectConfig(ctx, c)
	if err != nil {
		return nil, fmt.Errorf("connect to %s:%d/%s failed (check DB_* and PostgreSQL availability)", c.Host, c.Port, c.Database)
	}
	return &databaseSink{conn: conn}, nil
}

func (s *databaseSink) prepare(ctx context.Context, c config) error {
	var recovery, locked bool
	if err := s.conn.QueryRow(ctx, "SELECT pg_is_in_recovery()").Scan(&recovery); err != nil {
		return err
	}
	if recovery {
		return fmt.Errorf("target is a read-only replica")
	}
	if err := s.conn.QueryRow(ctx, "SELECT pg_try_advisory_lock($1)", generatorLock).Scan(&locked); err != nil {
		return err
	}
	if !locked {
		return fmt.Errorf("another Go generator is already running")
	}
	// Read-only preflight refuses an occupied DB before taking table locks or
	// reserving IDs. No cleanup path ever truncates, drops or updates existing data.
	if err := s.requireEmpty(ctx, s.conn); err != nil {
		return err
	}
	tx, err := s.conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background())
	// A brief lock closes the empty-check/sequence-reservation race. It is released
	// before generation. New application inserts then receive IDs above our range.
	for _, table := range dataTables {
		if _, err = tx.Exec(ctx, "LOCK TABLE "+pgx.Identifier{"public", table}.Sanitize()+" IN SHARE ROW EXCLUSIVE MODE"); err != nil {
			return err
		}
	}
	if err = s.requireEmpty(ctx, tx); err != nil {
		return err
	}
	for _, entry := range []struct {
		table string
		n     int
	}{{"categories", 50}, {"warehouses", 5}, {"users", c.Users}, {"products", c.Products}, {"orders", c.Orders}} {
		var sequence string
		if err = tx.QueryRow(ctx, "SELECT pg_get_serial_sequence($1,'id')", "public."+entry.table).Scan(&sequence); err != nil {
			return err
		}
		var last int64
		var called bool
		// Resolve and quote sequence identifiers from the catalog, never SQL input.
		var schema, name string
		if err = tx.QueryRow(ctx, "SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.oid=$1::regclass", sequence).Scan(&schema, &name); err != nil {
			return err
		}
		if err = tx.QueryRow(ctx, "SELECT last_value,is_called FROM "+pgx.Identifier{schema, name}.Sanitize()).Scan(&last, &called); err != nil {
			return err
		}
		if last != 1 || called {
			return fmt.Errorf("%s identity has already been used; use a freshly initialized separate database", entry.table)
		}
	}
	settings, _ := json.Marshal(struct {
		Engine string
		Config config
	}{"go", c})
	if err = tx.QueryRow(ctx, "INSERT INTO data_generator_runs(status,settings) VALUES ('RUNNING',$1::jsonb) RETURNING id", string(settings)).Scan(&s.runID); err != nil {
		return err
	}
	for _, entry := range []struct {
		table string
		n     int
	}{{"categories", 50}, {"warehouses", 5}, {"users", c.Users}, {"products", c.Products}, {"orders", c.Orders}} {
		if entry.n > 0 {
			if _, err = tx.Exec(ctx, "SELECT setval(pg_get_serial_sequence($1,'id'),$2,true)", "public."+entry.table, entry.n); err != nil {
				return err
			}
		}
	}
	return tx.Commit(ctx)
}

type querier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func (s *databaseSink) requireEmpty(ctx context.Context, q querier) error {
	if err := requireEmptyData(ctx, q); err != nil {
		return err
	}
	var pending bool
	if err := q.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM data_generator_runs WHERE status='RUNNING' OR (deferred_ddl IS NOT NULL AND deferred_ddl <> '{}'::jsonb AND deferred_ddl <> '[]'::jsonb))").Scan(&pending); err != nil {
		return err
	}
	if pending {
		return fmt.Errorf("unfinished generator run/deferred DDL detected; use a new database")
	}
	return nil
}

func requireEmptyData(ctx context.Context, q querier) error {
	for _, table := range dataTables {
		var exists bool
		if err := q.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM "+pgx.Identifier{"public", table}.Sanitize()+" LIMIT 1)").Scan(&exists); err != nil {
			return fmt.Errorf("schema check %s: %w (initialize schema/index SQL in a separate DB first)", table, err)
		}
		if exists {
			return fmt.Errorf("database contains data in %s; refusing to write. Use --dry-run or a new, separately initialized DB; no data was deleted", table)
		}
	}
	return nil
}
func (s *databaseSink) Write(ctx context.Context, b *batch) error {
	tx, err := s.conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = tx.Rollback(cleanup)
	}()
	for _, t := range b.tables {
		if t.rows == 0 {
			continue
		}
		// Table/column names are static strings declared in the generator source.
		tag, err := s.conn.PgConn().CopyFrom(ctx, bytes.NewReader(t.data.Bytes()), "COPY "+pgx.Identifier{"public", t.name}.Sanitize()+" ("+t.columns+") FROM STDIN")
		if err != nil {
			return fmt.Errorf("COPY %s: %w", t.name, err)
		}
		if tag.RowsAffected() != t.rows {
			return fmt.Errorf("COPY %s returned %d rows, expected %d", t.name, tag.RowsAffected(), t.rows)
		}
	}
	return tx.Commit(ctx)
}
func (s *databaseSink) finish(ctx context.Context, counts map[string]int64, runErr error) error {
	if s.runID == 0 {
		return nil
	}
	status := "COMPLETED"
	var message any
	if runErr != nil {
		status = "FAILED"
		message = runErr.Error()
	}
	rows, _ := json.Marshal(counts)
	_, err := s.conn.Exec(ctx, "UPDATE data_generator_runs SET status=$1,row_counts=$2::jsonb,error=$3,finished_at=now() WHERE id=$4", status, string(rows), message, s.runID)
	if err != nil {
		return err
	}
	return nil
}
