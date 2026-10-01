package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
)

func run(ctx context.Context, args []string) error {
	c, err := parseConfig(args, os.Stdout)
	if err != nil {
		return err
	}
	if !c.DryRun {
		if reset := strings.ToLower(strings.TrimSpace(os.Getenv("RESET_DATA"))); reset == "true" || reset == "1" || reset == "yes" || reset == "on" {
			return errors.New("RESET_DATA is enabled; this generator has no reset/delete mode. Unset it and use a new database")
		}
		if !c.RestoreSchema && strings.EqualFold(os.Getenv("AUTO_GENERATE"), "false") {
			fmt.Println("AUTO_GENERATE=false: nothing to do")
			return nil
		}
	}
	fmt.Printf("Go generator: profile=%s workers=%d batch=%d seed=%d DATA_NOW=%s dry-run=%t\n", c.Profile, c.Workers, c.Batch, c.Seed, c.Now.Format(time.RFC3339), c.DryRun)
	fmt.Printf("Requested: users=%d products=%d inventory=%d orders=%d order_items=%d reviews=%d\n", c.Users, c.Products, c.Inventory, c.Orders, c.Items, c.Reviews)
	var writer sink = discardSink{}
	var db *databaseSink
	if !c.DryRun {
		db, err = openDB(ctx)
		if err != nil {
			return err
		}
		defer func() {
			closeCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			db.conn.Close(closeCtx)
		}()
		if c.RestoreSchema {
			if err = db.restoreSchema(ctx); err != nil {
				return err
			}
			fmt.Println("Recorded Go indexes/constraints restored; no rows generated or removed.")
			return nil
		}
		if err = db.prepare(ctx, c); err != nil {
			return err
		}
		writer = db
	}
	started := time.Now()
	e := newEngine(c, writer, os.Stdout)
	var runErr error
	if db != nil && c.BulkLoad {
		runErr = db.deferSchema(ctx)
	}
	if runErr == nil {
		runErr = e.run(ctx)
	}
	if db != nil {
		if c.BulkLoad && ctx.Err() == nil {
			runErr = errors.Join(runErr, db.restoreSchema(ctx))
		}
		if runErr == nil && c.Analyze {
			for _, table := range dataTables {
				if _, err = db.conn.Exec(ctx, "ANALYZE "+pgx.Identifier{"public", table}.Sanitize()); err != nil {
					runErr = err
					break
				}
			}
		}
		finishCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err = db.finish(finishCtx, e.counts, runErr); err != nil {
			runErr = errors.Join(runErr, err)
		}
	}
	if runErr != nil {
		return fmt.Errorf("generation stopped; committed batches are preserved. If bulk load was interrupted, run --restore-schema on the same DB: %w", runErr)
	}
	var total int64
	for _, table := range dataTables {
		n := e.counts[table]
		total += n
		fmt.Printf("  %-14s %12d\n", table, n)
	}
	fmt.Printf("Done: %d rows, %.1f MiB COPY payload, %.2fs, %.0f rows/s\n", total, float64(e.bytes)/(1024*1024), time.Since(started).Seconds(), float64(total)/time.Since(started).Seconds())
	if c.DryRun {
		fmt.Println("Dry run only: generated and encoded in memory; no DB connection, writes, WAL, index work or replication included.")
	}
	return nil
}
func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, os.Args[1:]); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return
		}
		fmt.Fprintln(os.Stderr, "ERROR:", err)
		os.Exit(1)
	}
}
