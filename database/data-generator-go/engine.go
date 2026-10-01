package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"math/rand/v2"
	"strings"
	"time"
)

// reference.json is a checked-in snapshot of generators/reference.py. Runtime
// does not need Python or Faker; both implementations share the lab vocabulary.
//
//go:embed reference.json
var referenceJSON []byte

type leaf struct {
	Name, Code string
	Nouns      []string
	PriceMin   float64 `json:"price_min"`
	PriceMax   float64 `json:"price_max"`
	Weight     int
}
type topCategory struct {
	Name, Code, Kind string
	Brands           []string
	WeightGrams      []int `json:"weight_grams"`
	Leaves           []leaf
}
type reference struct {
	Categories      []topCategory       `json:"CATEGORY_TREE"`
	Warehouses      [][]string          `json:"WAREHOUSES"`
	Adjectives      []string            `json:"ADJECTIVES"`
	Colors          []string            `json:"COLORS"`
	ColorWeights    []int               `json:"COLOR_WEIGHTS"`
	Materials       []string            `json:"MATERIALS"`
	HomeMaterials   []string            `json:"HOME_MATERIALS"`
	Tags            []string            `json:"PRODUCT_TAGS"`
	Features        []string            `json:"FEATURES"`
	Benefits        []string            `json:"BENEFITS"`
	Domains         []string            `json:"EMAIL_DOMAINS"`
	DomainWeights   []int               `json:"EMAIL_DOMAIN_WEIGHTS"`
	Sources         []string            `json:"SIGNUP_SOURCES"`
	SourceWeights   []int               `json:"SIGNUP_SOURCE_WEIGHTS"`
	Languages       []string            `json:"LANGUAGES"`
	LanguageWeights []int               `json:"LANGUAGE_WEIGHTS"`
	Coupons         []string            `json:"COUPONS"`
	CouponWeights   []int               `json:"COUPON_WEIGHTS"`
	Titles          map[string][]string `json:"REVIEW_TITLES"`
	Sentences       map[string][]string `json:"REVIEW_SENTENCES"`
}
type category struct {
	id   int
	top  topCategory
	leaf leaf
}
type productInfo struct {
	price   int64
	status  uint8
	quality uint8
}
type purchase struct {
	user, product int32
	order, at     int64
}
type engine struct {
	cfg          config
	ref          reference
	log          io.Writer
	sink         sink
	counts       map[string]int64
	bytes        int64
	leaves       []category
	leafWeights  []int
	heavy, light []int32
	heavyFlags   []bool
	products     []productInfo
	ranking      []int32
	headers      []orderHeader
	plans        []purchase
	seen         map[uint64]struct{}
}

const day = int64(86400)

func newEngine(c config, s sink, log io.Writer) *engine {
	e := &engine{cfg: c, sink: s, log: log, counts: make(map[string]int64)}
	if err := json.Unmarshal(referenceJSON, &e.ref); err != nil {
		panic(err)
	}
	for ti, t := range e.ref.Categories {
		for li, l := range t.Leaves {
			e.leaves = append(e.leaves, category{ti*5 + li + 2, t, l})
			e.leafWeights = append(e.leafWeights, l.Weight)
		}
	}
	return e
}
func (e *engine) rng(kind, id uint64) *rand.Rand {
	return rand.New(rand.NewPCG(e.cfg.Seed^kind*0x9e3779b97f4a7c15, id+0x517cc1b727220a95))
}
func pick[T any](r *rand.Rand, v []T) T { return v[r.IntN(len(v))] }
func weighted(r *rand.Rand, w []int) int {
	total := 0
	for _, v := range w {
		total += v
	}
	n := r.IntN(total)
	for i, v := range w {
		n -= v
		if n < 0 {
			return i
		}
	}
	panic("empty distribution")
}
func chance(r *rand.Rand, p float64) bool { return r.Float64() < p }
func between(r *rand.Rand, lo, hi int64) int64 {
	if hi <= lo {
		return lo
	}
	return lo + int64(float64(hi-lo)*math.Pow(r.Float64(), .7))
}
func stamp(seconds int64) time.Time { return time.Unix(seconds, 0).UTC() }
func slug(s string) string {
	var b strings.Builder
	dash := false
	for _, c := range strings.ToLower(s) {
		if c >= 'a' && c <= 'z' || c >= '0' && c <= '9' {
			b.WriteRune(c)
			dash = false
		} else if b.Len() > 0 && !dash {
			b.WriteByte('-')
			dash = true
		}
	}
	return strings.Trim(b.String(), "-")
}
func (e *engine) userCreated(i int) int64 {
	old := e.cfg.Now.Unix() - 1460*day
	return old + int64(float64(1460*day-3600)*math.Pow((float64(i)+.5)/float64(e.cfg.Users), .6))
}

// All catalog launches precede order history, so no full-table UPDATE is needed
// after loading. Creation dates still increase with product IDs.
func (e *engine) productCreated(i int) int64 {
	return e.cfg.Now.Unix() - 1460*day + int64(float64(364*day)*(float64(i)+.5)/float64(e.cfg.Products))
}
func (e *engine) pickBuyer(r *rand.Rand) int32 {
	pool := e.light
	if len(pool) == 0 || chance(r, e.cfg.HeavyOrders) {
		pool = e.heavy
	}
	return pick(r, pool)
}

func (e *engine) run(ctx context.Context) error {
	steps := []struct {
		name string
		fn   func(context.Context) error
	}{
		{"catalog", e.catalog}, {"users", e.users}, {"products", e.generateProducts}, {"orders", e.orders}, {"reviews", e.reviews},
	}
	for _, s := range steps {
		if err := ctx.Err(); err != nil {
			return err
		}
		fmt.Fprintln(e.log, "Generating", s.name+"...")
		if err := s.fn(ctx); err != nil {
			return fmt.Errorf("%s: %w", s.name, err)
		}
	}
	return nil
}

func (e *engine) catalog(ctx context.Context) error {
	c := &copyTable{name: "categories", columns: "id,parent_id,name,slug,description,is_active,sort_order,created_at"}
	w := &copyTable{name: "warehouses", columns: "id,code,name,city,country_code,is_active,created_at"}
	created := stamp(e.cfg.Now.Unix() - 1495*day)
	for ti, t := range e.ref.Categories {
		id := ti*5 + 1
		c.row(id, nilValue, t.Name, slug(t.Name), "All "+strings.ToLower(t.Name)+" products", true, ti+1, created)
		for li, l := range t.Leaves {
			c.row(id+li+1, id, l.Name, slug(t.Name)+"-"+slug(l.Name), l.Name+" in "+t.Name, true, li+1, created)
		}
	}
	for i, v := range e.ref.Warehouses {
		w.row(i+1, v[0], v[1], v[2], v[3], true, created)
	}
	b := &batch{tables: []*copyTable{c, w}}
	if err := e.sink.Write(ctx, b); err != nil {
		return err
	}
	for _, t := range b.tables {
		e.counts[t.name] += t.rows
		e.bytes += int64(t.data.Len())
	}
	return nil
}
