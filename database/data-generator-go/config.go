package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"math"
	"os"
	"runtime"
	"strconv"
	"time"
)

type config struct {
	Profile                                            string
	Users, Products, Inventory, Orders, Items, Reviews int
	Batch, Workers                                     int
	Seed                                               uint64
	Now                                                time.Time
	HeavyShare, HeavyOrders                            float64
	DryRun, Analyze                                    bool
	BulkLoad, RestoreSchema                            bool
}

func parseConfig(args []string, out io.Writer) (config, error) {
	c := config{Profile: "default", Users: 100000, Products: 100000, Inventory: 100000,
		Orders: 500000, Items: 1500000, Reviews: 300000, Batch: 10000,
		Workers: min(4, runtime.GOMAXPROCS(0)), Seed: 42, Now: time.Now().UTC().Truncate(time.Second),
		HeavyShare: .2, HeavyOrders: .7}
	if len(args) > 0 && args[0] != "" && args[0][0] != '-' {
		c.Profile, args = args[0], args[1:]
	}
	switch c.Profile {
	case "small":
		c.Users, c.Products, c.Inventory, c.Orders, c.Items, c.Reviews = 10000, 10000, 10000, 50000, 150000, 30000
	case "5m":
		c.Users, c.Products, c.Inventory, c.Orders, c.Items, c.Reviews, c.Batch = 5000000, 5000000, 5000000, 5000000, 10000000, 5000000, 50000
	case "default", "custom":
	default:
		return c, fmt.Errorf("unknown profile %q (small|default|5m|custom)", c.Profile)
	}
	ints := map[string]*int{"GO_WORKERS": &c.Workers, "BATCH_SIZE": &c.Batch}
	if c.Profile == "custom" {
		for k, v := range map[string]*int{"NUM_USERS": &c.Users, "NUM_PRODUCTS": &c.Products, "NUM_INVENTORY": &c.Inventory, "NUM_ORDERS": &c.Orders, "NUM_ORDER_ITEMS": &c.Items, "NUM_REVIEWS": &c.Reviews} {
			ints[k] = v
		}
	}
	for k, p := range ints {
		if s := os.Getenv(k); s != "" {
			n, err := strconv.Atoi(s)
			if err != nil {
				return c, fmt.Errorf("%s: %w", k, err)
			}
			*p = n
		}
	}
	if s := os.Getenv("SEED"); s != "" {
		n, err := strconv.ParseUint(s, 10, 64)
		if err != nil {
			return c, fmt.Errorf("SEED: %w", err)
		}
		c.Seed = n
	}
	for k, p := range map[string]*float64{"HEAVY_USER_SHARE": &c.HeavyShare, "HEAVY_USER_ORDER_SHARE": &c.HeavyOrders} {
		if s := os.Getenv(k); s != "" {
			v, err := strconv.ParseFloat(s, 64)
			if err != nil {
				return c, fmt.Errorf("%s: %w", k, err)
			}
			*p = v
		}
	}
	now := os.Getenv("DATA_NOW")
	f := flag.NewFlagSet("generate-data-go [small|default|5m|custom]", flag.ContinueOnError)
	f.SetOutput(out)
	f.IntVar(&c.Workers, "workers", c.Workers, "parallel CPU workers (COPY uses one ordered writer)")
	f.IntVar(&c.Batch, "batch-size", c.Batch, "parent rows per transaction")
	f.BoolVar(&c.DryRun, "dry-run", false, "generate and encode all rows without connecting to a database")
	f.BoolVar(&c.Analyze, "analyze", false, "ANALYZE loaded tables after success (no VACUUM)")
	f.BoolVar(&c.BulkLoad, "bulk-load", false, "temporarily defer secondary indexes/UNIQUE/FKs in a fresh, dedicated DB")
	f.BoolVar(&c.RestoreSchema, "restore-schema", false, "restore recorded Go bulk-load indexes/constraints only; generate no rows")
	f.StringVar(&now, "data-now", now, "fixed RFC3339 reference timestamp for reproducible data")
	if err := f.Parse(args); err != nil {
		return c, err
	}
	if f.NArg() != 0 {
		return c, fmt.Errorf("unexpected arguments: %v", f.Args())
	}
	if now != "" {
		t, err := time.Parse(time.RFC3339, now)
		if err != nil {
			return c, fmt.Errorf("DATA_NOW: %w", err)
		}
		c.Now = t.UTC().Truncate(time.Second)
	}
	return c, c.validate()
}

func (c config) validate() error {
	if c.RestoreSchema && (c.DryRun || c.BulkLoad) {
		return errors.New("--restore-schema cannot be combined with --dry-run or --bulk-load")
	}
	if c.Users < 1 || c.Products < 1 || c.Users > math.MaxInt32 || c.Products > math.MaxInt32 {
		return errors.New("NUM_USERS and NUM_PRODUCTS must be in [1, 2147483647]")
	}
	if c.Orders < 0 || c.Items < 0 || c.Inventory < 0 || c.Reviews < 0 {
		return errors.New("row counts cannot be negative")
	}
	if c.Orders > 999999999 {
		return errors.New("NUM_ORDERS cannot exceed 999999999 (order_number varchar(20))")
	}
	if c.Batch < 1 || c.Workers < 1 || c.Workers > 64 {
		return errors.New("batch-size must be positive; workers must be in [1,64]")
	}
	if c.Inventory > c.Products*5 {
		return errors.New("NUM_INVENTORY cannot exceed NUM_PRODUCTS * 5 warehouses")
	}
	if (c.Orders == 0 && c.Items != 0) || c.Items < c.Orders || (c.Orders > 0 && (c.Items/c.Orders > c.Products || (c.Items/c.Orders == c.Products && c.Items%c.Orders != 0))) {
		return errors.New("order items require 1..NUM_PRODUCTS distinct products per order (zero items when zero orders)")
	}
	if int64(c.Reviews) > int64(c.Users)*int64(c.Products) {
		return errors.New("NUM_REVIEWS exceeds the number of unique user/product pairs")
	}
	if math.IsNaN(c.HeavyShare) || !(c.HeavyShare > 0 && c.HeavyShare < 1) || math.IsNaN(c.HeavyOrders) || !(c.HeavyOrders >= 0 && c.HeavyOrders <= 1) {
		return errors.New("HEAVY_USER_SHARE must be in (0,1); HEAVY_USER_ORDER_SHARE in [0,1]")
	}
	return nil
}
