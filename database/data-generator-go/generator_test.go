package main

import (
	"context"
	"io"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"
)

type captureSink map[string]string

func (s captureSink) Write(ctx context.Context, b *batch) error {
	for _, table := range b.tables {
		s[table.name] += table.data.String()
	}
	return ctx.Err()
}
func testConfig() config {
	return config{Users: 80, Products: 60, Inventory: 130, Orders: 240, Items: 723, Reviews: 200, Batch: 17, Workers: 3, Seed: 42, Now: time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC), HeavyShare: .2, HeavyOrders: .7}
}
func generate(t *testing.T, c config) (*engine, captureSink) {
	t.Helper()
	if err := c.validate(); err != nil {
		t.Fatal(err)
	}
	s := captureSink{}
	e := newEngine(c, s, io.Discard)
	if err := e.run(context.Background()); err != nil {
		t.Fatal(err)
	}
	return e, s
}
func rows(s string) [][]string {
	if s == "" {
		return nil
	}
	lines := strings.Split(strings.TrimSuffix(s, "\n"), "\n")
	out := make([][]string, len(lines))
	for i, line := range lines {
		out[i] = strings.Split(line, "\t")
	}
	return out
}
func integer(s string) int64 {
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		panic(err)
	}
	return v
}
func cents(s string) int64 {
	parts := strings.Split(s, ".")
	return integer(parts[0])*100 + integer(parts[1])
}
func when(s string) time.Time {
	v, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		panic(err)
	}
	return v
}

func TestRelationalAndFinancialConsistency(t *testing.T) {
	c := testConfig()
	e, s := generate(t, c)
	for table, want := range map[string]int64{"categories": 50, "warehouses": 5, "users": 80, "products": 60, "inventory": 130, "orders": 240, "order_items": 723, "reviews": 200} {
		if e.counts[table] != want {
			t.Fatalf("%s count %d, want %d", table, e.counts[table], want)
		}
	}
	users, products, orders := map[string][]string{}, map[string][]string{}, map[string][]string{}
	defaults, inventory := map[string]int{}, map[string]int64{}
	for _, r := range rows(s["users"]) {
		users[r[0]] = r
	}
	for _, r := range rows(s["addresses"]) {
		if users[r[0]] == nil {
			t.Fatal("orphan address")
		}
		if r[10] == "t" {
			defaults[r[0]]++
		}
	}
	for id := range users {
		if defaults[id] != 1 {
			t.Fatal("default address invariant")
		}
	}
	for _, r := range rows(s["inventory"]) {
		inventory[r[0]] += integer(r[2])
		if integer(r[3]) > integer(r[2]) {
			t.Fatal("reserved stock invariant")
		}
	}
	for _, r := range rows(s["products"]) {
		products[r[0]] = r
		if inventory[r[0]] != integer(r[8]) {
			t.Fatal("stock invariant")
		}
	}
	for _, r := range rows(s["orders"]) {
		orders[r[0]] = r
		if users[r[1]] == nil || when(r[12]).Before(when(users[r[1]][14])) {
			t.Fatal("order signup invariant")
		}
		if cents(r[4])-cents(r[5])+cents(r[6]) != cents(r[7]) {
			t.Fatal("order total invariant")
		}
	}
	subtotals := map[string]int64{}
	pairs := map[string]bool{}
	for _, r := range rows(s["order_items"]) {
		o, p := orders[r[0]], products[r[1]]
		if o == nil || p == nil {
			t.Fatal("orphan item")
		}
		if p[9] == "DRAFT" || when(o[12]).Before(when(p[13])) {
			t.Fatal("product sale invariant")
		}
		if integer(r[2])*cents(r[3])-cents(r[4]) != cents(r[5]) {
			t.Fatal("line total invariant")
		}
		subtotals[r[0]] += cents(r[5])
		key := r[0] + ":" + r[1]
		if pairs[key] {
			t.Fatal("duplicate order/product")
		}
		pairs[key] = true
	}
	paid, attempts := map[string]bool{}, map[string]int{}
	for _, r := range rows(s["payments"]) {
		o := orders[r[0]]
		if o == nil || cents(r[2]) != cents(o[7]) || when(r[7]).Before(when(o[12])) {
			t.Fatal("payment invariant")
		}
		attempts[r[0]]++
		if r[3] == "SUCCEEDED" {
			paid[r[0]] = true
		}
		if (r[3] == "SUCCEEDED" || r[3] == "REFUNDED") != (r[6] != `\N`) {
			t.Fatal("paid_at invariant")
		}
	}
	for id, o := range orders {
		if subtotals[id] != cents(o[4]) || attempts[id] == 0 || o[3] == "COMPLETED" && !paid[id] {
			t.Fatal("order items/payment invariant")
		}
	}
	reviews := map[string]bool{}
	verified := 0
	for _, r := range rows(s["reviews"]) {
		p, u := products[r[0]], users[r[1]]
		key := r[1] + ":" + r[0]
		if reviews[key] {
			t.Fatal("duplicate review")
		}
		reviews[key] = true
		if p == nil || u == nil || when(r[8]).Before(when(p[13])) || when(r[8]).Before(when(u[14])) {
			t.Fatal("review date invariant")
		}
		if r[6] == "t" {
			verified++
			o := orders[r[2]]
			if o == nil || o[1] != r[1] || o[3] != "COMPLETED" || !pairs[r[2]+":"+r[0]] || when(r[8]).Before(when(o[12])) {
				t.Fatal("verified purchase invariant")
			}
		}
	}
	if verified == 0 {
		t.Fatal("expected verified reviews")
	}
}
func TestDeterministicAcrossWorkersAndBatches(t *testing.T) {
	c := testConfig()
	_, first := generate(t, c)
	c.Workers = 1
	c.Batch = 29
	_, second := generate(t, c)
	if !reflect.DeepEqual(first, second) {
		for table := range first {
			if first[table] != second[table] {
				t.Errorf("%s changed with worker/batch size", table)
			}
		}
	}
}
func TestTinyAndDenseProfilesTerminate(t *testing.T) {
	for _, n := range []int{1, 3, 10} {
		c := testConfig()
		c.Users = n
		c.Products = n
		c.Orders = n
		c.Items = n * n
		c.Reviews = n * n
		c.Inventory = n * 5
		e, _ := generate(t, c)
		if e.counts["reviews"] != int64(n*n) {
			t.Fatal("missing reviews")
		}
	}
}
func TestNoOrders(t *testing.T) {
	c := testConfig()
	c.Orders = 0
	c.Items = 0
	c.Inventory = 0
	e, s := generate(t, c)
	if e.counts["orders"] != 0 || e.counts["inventory"] != 0 {
		t.Fatal("unexpected rows")
	}
	for _, r := range rows(s["reviews"]) {
		if r[2] != `\N` || r[6] != "f" {
			t.Fatal("unbacked verified review")
		}
	}
}
func TestCopyEscapingAndMoney(t *testing.T) {
	table := &copyTable{}
	table.row(nil, `\N`, "a\tb\nc\rd\\e", money(10005), []string{"a,b", `a"b`, `a\b`})
	want := "\\N\t\\\\N\ta\\tb\\nc\\rd\\\\e\t100.05\t{\"a,b\",\"a\\\\\"b\",\"a\\\\\\\\b\"}\n"
	if table.data.String() != want {
		t.Fatalf("got %q; want %q", table.data.String(), want)
	}
}
func TestRejectInvalidSizes(t *testing.T) {
	for _, modify := range []func(*config){func(c *config) { c.Items = c.Orders - 1 }, func(c *config) { c.Orders = 0 }, func(c *config) { c.Inventory = c.Products*5 + 1 }, func(c *config) { c.Reviews = c.Users*c.Products + 1 }, func(c *config) { c.Workers = 0 }, func(c *config) { c.Batch = 0 }, func(c *config) { c.HeavyShare = 1 }} {
		c := testConfig()
		modify(&c)
		if c.validate() == nil {
			t.Fatal("expected validation error")
		}
	}
}
func TestCancellation(t *testing.T) {
	c := testConfig()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	s := captureSink{}
	if err := newEngine(c, s, io.Discard).run(ctx); err != context.Canceled {
		t.Fatalf("got %v", err)
	}
	if len(s) != 0 {
		t.Fatal("wrote after cancellation")
	}
}

func TestConnectionFallbacksStayOnRequestedTarget(t *testing.T) {
	t.Setenv("DB_HOST", "target.invalid")
	t.Setenv("DB_PORT", "55432")
	t.Setenv("DB_NAME", "fresh_database")
	t.Setenv("DB_USER", "test_user")
	t.Setenv("DB_PASSWORD", "spaces and 'quotes' @ / : ?")
	t.Setenv("PGHOST", "unrelated.invalid")
	t.Setenv("PGPORT", "5432")
	t.Setenv("PGSSLMODE", "prefer")
	c, err := connectionConfig()
	if err != nil {
		t.Fatal(err)
	}
	if c.Host != "target.invalid" || c.Port != 55432 || c.Database != "fresh_database" || c.Password != "spaces and 'quotes' @ / : ?" {
		t.Fatal("connection target/password not preserved")
	}
	for _, f := range c.Fallbacks {
		if f.Host != c.Host || f.Port != c.Port {
			t.Fatalf("fallback points to %s:%d", f.Host, f.Port)
		}
	}
}

func TestProfileAndOptionValidation(t *testing.T) {
	for _, k := range []string{"GO_WORKERS", "BATCH_SIZE", "SEED", "DATA_NOW", "HEAVY_USER_SHARE", "HEAVY_USER_ORDER_SHARE"} {
		t.Setenv(k, "")
	}
	c, err := parseConfig([]string{"5m", "--dry-run", "--workers", "2"}, io.Discard)
	if err != nil || c.Users != 5000000 || c.Items != 10000000 || c.Batch != 50000 || c.Workers != 2 || !c.DryRun {
		t.Fatalf("profile config: %+v / %v", c, err)
	}
	for _, args := range [][]string{{"--restore-schema", "--dry-run"}, {"--restore-schema", "--bulk-load"}, {"small", "--reset"}, {"5mm"}, {""}} {
		if _, err := parseConfig(args, io.Discard); err == nil {
			t.Fatalf("accepted invalid args %v", args)
		}
	}
}
func BenchmarkGenerateAndEncode(b *testing.B) {
	c := testConfig()
	c.Users = 1000
	c.Products = 1000
	c.Inventory = 1000
	c.Orders = 5000
	c.Items = 15000
	c.Reviews = 3000
	c.Batch = 1000
	for b.Loop() {
		if err := newEngine(c, discardSink{}, io.Discard).run(context.Background()); err != nil {
			b.Fatal(err)
		}
	}
}
