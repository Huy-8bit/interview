package main

import (
	"context"
	"fmt"
	"slices"
	"strings"
)

func (e *engine) reviews(ctx context.Context) error {
	r := e.rng(8, 0)
	verified := len(e.plans)
	for i := range e.plans {
		e.plans[i].at = min(e.plans[i].at+3*day+r.Int64N(42*day), e.cfg.Now.Unix())
	}
	// Random attempts retain buyer/product skew; a permutation of the finite
	// pair space fills the remainder when custom profiles are close to saturation.
	var fallback uint64
	maxPairs := uint64(e.cfg.Users) * uint64(e.cfg.Products)
	for attempts := 0; len(e.plans) < e.cfg.Reviews; attempts++ {
		if attempts%4096 == 0 {
			if err := ctx.Err(); err != nil {
				return err
			}
		}
		var user, product int32
		if attempts < e.cfg.Reviews*5 {
			user = int32(r.IntN(e.cfg.Users))
			if chance(r, .5) {
				user = e.pickBuyer(r)
			}
			product = int32(r.IntN(e.cfg.Products))
		} else {
			for fallback < maxPairs {
				if _, ok := e.seen[fallback]; !ok {
					break
				}
				fallback++
			}
			if fallback == maxPairs {
				return fmt.Errorf("not enough unique review pairs")
			}
			user = int32(fallback / uint64(e.cfg.Products))
			product = int32(fallback % uint64(e.cfg.Products))
			fallback++
		}
		key := e.pairKey(user, product)
		if _, ok := e.seen[key]; ok {
			continue
		}
		e.seen[key] = struct{}{}
		lo := max(e.userCreated(int(user)), e.productCreated(int(product)))
		e.plans = append(e.plans, purchase{user, product, 0, between(r, lo, e.cfg.Now.Unix())})
	}
	e.seen = nil
	slices.SortStableFunc(e.plans, func(a, b purchase) int {
		if a.at < b.at {
			return -1
		}
		if a.at > b.at {
			return 1
		}
		return 0
	})
	err := e.batches(ctx, "reviews", len(e.plans), func(lo, hi int) *batch {
		t := &copyTable{name: "reviews", columns: "product_id,user_id,order_id,rating,title,body,is_verified_purchase,helpful_count,created_at"}
		for i := lo; i < hi; i++ {
			r := e.rng(9, uint64(i))
			p := e.plans[i]
			weights := [][]int{{30, 18, 20, 17, 15}, {7, 5, 11, 27, 50}, {2, 2, 5, 21, 70}}[e.products[p.product].quality]
			rating := 1 + weighted(r, weights)
			mood := "positive"
			if rating == 3 {
				mood = "neutral"
			} else if rating < 3 {
				mood = "negative"
			}
			var title, body, order any
			if chance(r, .9) {
				title = pick(r, e.ref.Titles[mood])
			}
			if chance(r, .8) {
				parts := []string{}
				for j, n := 0, 1+r.IntN(3); j < n; j++ {
					parts = append(parts, pick(r, e.ref.Sentences[mood]))
				}
				body = strings.Join(parts, " ")
			}
			helpful := 0
			if chance(r, .3) {
				helpful = int(r.ExpFloat64() * 8)
			}
			if p.order > 0 {
				order = p.order
			}
			t.row(p.product+1, p.user+1, order, rating, title, body, p.order > 0, helpful, stamp(p.at))
		}
		return &batch{tables: []*copyTable{t}}
	}, nil)
	fmt.Fprintf(e.log, "  verified reviews: %d / %d\n", verified, e.cfg.Reviews)
	e.plans = nil
	return err
}
