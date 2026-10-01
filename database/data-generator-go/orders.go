package main

import (
	"context"
	"fmt"
	"math/rand/v2"
	"slices"
	"time"
)

type orderHeader struct {
	at     int64
	user   int32
	status uint8
}

var orderStatuses = []string{"PENDING", "CONFIRMED", "PROCESSING", "SHIPPED", "COMPLETED", "CANCELLED"}
var methods = []string{"CREDIT_CARD", "DEBIT_CARD", "E_WALLET", "BANK_TRANSFER", "COD", "PAYPAL"}
var couponPercent = []int64{10, 15, 0, 25, 20, 10}

func (e *engine) planOrders(ctx context.Context) error {
	e.headers = make([]orderHeader, e.cfg.Orders)
	r := e.rng(6, 0)
	now := e.cfg.Now.Unix()
	for i := range e.headers {
		if i%4096 == 0 {
			if err := ctx.Err(); err != nil {
				return err
			}
		}
		u := e.pickBuyer(r)
		s := weighted(r, []int{5, 5, 7, 13, 60, 10})
		age := []int64{10, 20, 45, 90, 1095, 1095}[s]
		minAge := []int64{0, 0, day / 2, day, 3 * day, 0}[s]
		lo, hi := max(e.userCreated(int(u)), now-age*day), now-minAge
		if lo >= hi {
			s = 0
			lo = e.userCreated(int(u))
			hi = now
		}
		at := between(r, lo, hi)
		if s >= 4 && chance(r, .1) {
			for attempt := 0; attempt < 8; attempt++ {
				year := e.cfg.Now.Year() - r.IntN(4)
				holiday := time.Date(year, 11, 24, 0, 0, 0, 0, time.UTC).Unix() + r.Int64N(32*day)
				if holiday >= lo && holiday <= hi {
					at = holiday
					break
				}
			}
		}
		// Evening shopping peak, while respecting signup/status age bounds.
		hour := r.IntN(24)
		if chance(r, .5) {
			hour = 18 + r.IntN(5)
		}
		withHour := at/day*day + int64(hour)*3600 + r.Int64N(3600)
		if withHour >= lo && withHour <= hi {
			at = withHour
		}
		e.headers[i] = orderHeader{at, u, uint8(s)}
	}
	slices.SortStableFunc(e.headers, func(a, b orderHeader) int {
		if a.at < b.at {
			return -1
		}
		if a.at > b.at {
			return 1
		}
		return 0
	})
	return ctx.Err()
}

func (e *engine) orders(ctx context.Context) error {
	if err := e.planOrders(ctx); err != nil {
		return err
	}
	e.seen = make(map[uint64]struct{})
	maxVerified := e.cfg.Reviews * 3 / 4
	err := e.batches(ctx, "orders", e.cfg.Orders, func(lo, hi int) *batch {
		o := &copyTable{name: "orders", columns: "id,user_id,order_number,status,subtotal,discount,shipping_fee,total_amount,currency,coupon_code,shipping_address,note,created_at,updated_at"}
		items := &copyTable{name: "order_items", columns: "order_id,product_id,quantity,unit_price,discount,total_price"}
		p := &copyTable{name: "payments", columns: "order_id,payment_method,amount,status,transaction_id,provider_response,paid_at,created_at"}
		b := &batch{tables: []*copyTable{o, items, p}}
		for i := lo; i < hi; i++ {
			r := e.rng(7, uint64(i))
			h := e.headers[i]
			oid := int64(i + 1)
			status := orderStatuses[h.status]
			created := stamp(h.at)
			zipf := rand.NewZipf(r, 1.1, 50, uint64(len(e.ranking)-1))
			n := e.cfg.Items / e.cfg.Orders
			if i < e.cfg.Items%e.cfg.Orders {
				n++
			}
			chosen := make(map[int32]bool, n)
			var subtotal int64
			for j := 0; j < n; j++ {
				pid := e.ranking[zipf.Uint64()]
				// A bounded retry keeps tiny/dense custom profiles from hanging.
				for retry := 0; chosen[pid] && retry < 32; retry++ {
					pid = e.ranking[zipf.Uint64()]
				}
				if chosen[pid] {
					k := r.IntN(len(e.ranking))
					for chosen[e.ranking[k]] {
						k = (k + 1) % len(e.ranking)
					}
					pid = e.ranking[k]
				}
				chosen[pid] = true
				qty := int64(1 + weighted(r, []int{70, 18, 7, 3, 2}))
				unit := e.products[pid].price
				gross := qty * unit
				discount := int64(0)
				if chance(r, .12) {
					discount = gross * pick(r, []int64{5, 10, 15, 20}) / 100
				}
				total := gross - discount
				subtotal += total
				items.row(oid, pid+1, qty, money(unit), money(discount), money(total))
				if status == "COMPLETED" && maxVerified > 0 {
					b.purchases = append(b.purchases, purchase{h.user, pid, oid, h.at})
				}
			}
			_, _, address := e.userAddress(int(h.user), 0)
			var coupon any
			discount, shipping := int64(0), int64(0)
			if chance(r, .12) {
				ci := weighted(r, e.ref.CouponWeights)
				if ci == 3 && created.Month() != 11 && created.Month() != 12 {
					ci = 1
				}
				coupon = e.ref.Coupons[ci]
				discount = min(subtotal*couponPercent[ci]/100, 10000)
			}
			if coupon != "FREESHIP" && subtotal < 5000 {
				shipping = pick(r, []int64{499, 799})
				if address.Country != "US" {
					shipping = 1999
				}
			}
			total := subtotal - discount + shipping
			delay := []int64{0, 3600, day, 3 * day, 7 * day, day}[h.status]
			updated := min(h.at+delay, e.cfg.Now.Unix())
			var note any
			if chance(r, .04) {
				note = pick(r, []string{"Please leave the package at the front door.", "Gift wrap, please.", "Call before delivery.", "Deliver after 6pm."})
			}
			o.row(oid, h.user+1, fmt.Sprintf("ORD-%s-%08d", created.Format("060102"), oid), status, money(subtotal), money(discount), money(shipping), money(total), "USD", coupon, jsonText(address), note, created, stamp(updated))
			method := methods[weighted(r, []int{38, 12, 20, 10, 14, 6})]
			transactionID := func(attempt int) string {
				return fmt.Sprintf("%08x-0000-4000-8000-%012x", uint32(e.cfg.Seed), oid*2+int64(attempt))
			}
			if method != "COD" && chance(r, .03) {
				p.row(oid, method, money(total), "FAILED", transactionID(0), `{"provider":"stripe","error_code":"card_declined"}`, nilValue, stamp(min(h.at+5+r.Int64N(115), e.cfg.Now.Unix())))
			}
			payStatus := "SUCCEEDED"
			if status == "PENDING" || method == "COD" && (status == "CONFIRMED" || status == "PROCESSING" || status == "SHIPPED") {
				payStatus = "PENDING"
			} else if status == "CANCELLED" {
				payStatus = "REFUNDED"
				if method == "COD" || chance(r, .4) {
					payStatus = "FAILED"
				}
			}
			payCreated := min(h.at+130+r.Int64N(470), e.cfg.Now.Unix())
			var paidAt, txID any
			if payStatus != "PENDING" {
				txID = transactionID(1)
			}
			if payStatus == "SUCCEEDED" || payStatus == "REFUNDED" {
				paid := min(payCreated+1+r.Int64N(90), e.cfg.Now.Unix())
				if method == "COD" {
					paid = max(payCreated, updated)
				}
				paidAt = stamp(paid)
			}
			provider := map[string]any{"provider": map[string]string{"CREDIT_CARD": "stripe", "DEBIT_CARD": "stripe", "E_WALLET": "momo", "BANK_TRANSFER": "Chase", "COD": "UPS", "PAYPAL": "paypal"}[method]}
			if payStatus == "FAILED" {
				provider["error_code"] = "insufficient_funds"
			}
			if payStatus == "REFUNDED" {
				provider["refund"] = map[string]string{"reason": "customer_request"}
			}
			p.row(oid, method, money(total), payStatus, txID, jsonText(provider), paidAt, stamp(payCreated))
		}
		return b
	}, func(b *batch) {
		for _, p := range b.purchases {
			if len(e.plans) >= maxVerified {
				break
			}
			key := e.pairKey(p.user, p.product)
			if _, ok := e.seen[key]; ok {
				continue
			}
			e.seen[key] = struct{}{}
			e.plans = append(e.plans, p)
		}
	})
	e.headers = nil
	return err
}
func (e *engine) pairKey(user, product int32) uint64 {
	return uint64(user)*uint64(e.cfg.Products) + uint64(product)
}
