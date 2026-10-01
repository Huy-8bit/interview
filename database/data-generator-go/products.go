package main

import (
	"context"
	"fmt"
	"math"
	"math/rand/v2"
)

var productStatuses = []string{"ACTIVE", "OUT_OF_STOCK", "DISCONTINUED", "DRAFT"}

func (e *engine) attributes(r *rand.Rand, c category, brand string) string {
	a := map[string]any{"brand": brand}
	color := e.ref.Colors[weighted(r, e.ref.ColorWeights)]
	switch c.top.Kind {
	case "electronics":
		a["color"], a["warranty_months"] = color, pick(r, []int{6, 12, 12, 24, 36})
		switch c.leaf.Code {
		case "PHN":
			a["specs"] = map[string]any{"storage_gb": pick(r, []int{64, 128, 256, 512, 1024}), "ram_gb": pick(r, []int{4, 6, 8, 12, 16}), "screen_inches": 6.1, "5g": chance(r, .7)}
		case "LAP":
			a["specs"] = map[string]any{"ram_gb": pick(r, []int{8, 16, 16, 32, 64}), "storage_gb": pick(r, []int{256, 512, 1024, 2048}), "cpu": pick(r, []string{"Intel Core i5", "Intel Core i7", "AMD Ryzen 7", "Apple M4"}), "screen_inches": pick(r, []float64{13.3, 14, 15.6, 16, 17.3})}
		case "AUD":
			a["specs"] = map[string]any{"wireless": chance(r, .8), "noise_cancelling": chance(r, .4), "battery_hours": pick(r, []int{8, 12, 20, 30, 40})}
		default:
			a["specs"] = map[string]any{"megapixels": pick(r, []int{12, 20, 24, 33, 45, 61}), "video": pick(r, []string{"1080p", "4K", "4K", "8K"})}
		}
	case "fashion":
		a["color"], a["size"], a["material"], a["gender"] = color, pick(r, []string{"XS", "S", "M", "M", "L", "L", "XL"}), pick(r, e.ref.Materials), pick(r, []string{"men", "women", "unisex"})
	case "home":
		a["color"], a["material"], a["dimensions_cm"] = color, pick(r, e.ref.HomeMaterials), map[string]int{"w": 10 + r.IntN(190), "h": 5 + r.IntN(195), "d": 5 + r.IntN(95)}
		if c.leaf.Code == "KIT" {
			a["power_watts"] = pick(r, []int{600, 800, 1000, 1500, 1800})
		}
	case "beauty":
		a["volume_ml"], a["skin_type"], a["vegan"], a["cruelty_free"] = pick(r, []int{15, 30, 50, 100, 200, 400}), pick(r, []string{"all", "dry", "oily", "combination", "sensitive"}), chance(r, .35), chance(r, .6)
	case "sports":
		a["color"], a["material"], a["level"] = color, pick(r, e.ref.Materials), pick(r, []string{"beginner", "intermediate", "pro"})
	case "books":
		a["author"], a["format"], a["pages"], a["language"], a["isbn"] = pick(r, firstNames)+" "+pick(r, lastNames), pick(r, []string{"Paperback", "Paperback", "Hardcover", "eBook", "Audiobook"}), 24+r.IntN(876), pick(r, []string{"English", "English", "English", "English", "Vietnamese", "French"}), fmt.Sprintf("978%010d", r.Int64N(10000000000))
	case "toys":
		a["age_min"], a["pieces"], a["battery_required"] = pick(r, []int{3, 6, 8, 12, 14}), pick(r, []int{1, 50, 100, 500, 1000, 2000}), chance(r, .25)
	case "grocery":
		a["net_weight_g"], a["organic"], a["pack_size"], a["shelf_life_days"] = pick(r, []int{50, 100, 250, 500, 1000}), chance(r, .25), pick(r, []int{1, 1, 6, 12, 24}), pick(r, []int{30, 90, 180, 365, 730})
	case "automotive":
		a["compatible_makes"], a["warranty_months"] = []string{pick(r, []string{"Toyota", "Honda", "Ford", "BMW", "Tesla", "Hyundai"})}, pick(r, []int{0, 6, 12, 24})
	case "health":
		a["form"], a["servings"], a["vegan"] = pick(r, []string{"capsule", "tablet", "powder", "gummy", "device"}), pick(r, []int{30, 60, 90, 120}), chance(r, .3)
	}
	if chance(r, .08) {
		a["origin_country"] = pick(r, []string{"US", "CN", "VN", "DE", "JP", "KR", "IT"})
	}
	return jsonText(a)
}

func (e *engine) generateProducts(ctx context.Context) error {
	e.products = make([]productInfo, e.cfg.Products)
	err := e.batches(ctx, "products", e.cfg.Products, func(lo, hi int) *batch {
		p := &copyTable{name: "products", columns: "id,category_id,sku,name,description,brand,price,cost,stock_quantity,status,weight_grams,tags,attributes,created_at,updated_at"}
		inv := &copyTable{name: "inventory", columns: "product_id,warehouse_id,quantity,reserved_quantity,reorder_level,last_restocked_at,updated_at"}
		for i := lo; i < hi; i++ {
			r := e.rng(4, uint64(i))
			c := e.leaves[weighted(r, e.leafWeights)]
			brand := pick(r, c.top.Brands)
			noun := pick(r, c.leaf.Nouns)
			price := int64(math.Round(100 * math.Exp(math.Log(c.leaf.PriceMin)+(math.Log(c.leaf.PriceMax)-math.Log(c.leaf.PriceMin))*math.Pow(r.Float64(), 1.4))))
			if price >= 1000 && chance(r, .6) {
				price = price/100*100 + 99
			}
			cost := price * int64(35+r.IntN(41)) / 100
			status := weighted(r, []int{85, 5, 7, 3})
			minimum := 1
			if e.cfg.Orders > 0 {
				minimum = (e.cfg.Items + e.cfg.Orders - 1) / e.cfg.Orders
			}
			if i < minimum {
				status = 0
			} // even a one-product custom run can sell
			e.products[i] = productInfo{price: price, status: uint8(status), quality: uint8(weighted(r, []int{12, 68, 20}))}
			created := e.productCreated(i)
			n := e.cfg.Inventory / e.cfg.Products
			if i < e.cfg.Inventory%e.cfg.Products {
				n++
			}
			stock := 0
			offset := r.IntN(5)
			for j := 0; j < n; j++ {
				q := int(r.ExpFloat64() * 60)
				if status == 1 || status == 3 {
					q = 0
				}
				reserved := 0
				if q > 0 {
					reserved = r.IntN(q+1) / 4
				}
				stock += q
				inv.row(i+1, (offset+j)%5+1, q, reserved, 5+r.IntN(26), stamp(between(r, created, e.cfg.Now.Unix())), stamp(e.cfg.Now.Unix()))
			}
			tags := []string{}
			used := map[string]bool{}
			for j, n := 0, r.IntN(4); j < n; j++ {
				tag := pick(r, e.ref.Tags)
				if !used[tag] {
					used[tag] = true
					tags = append(tags, tag)
				}
			}
			var description, weight any
			if chance(r, .9) {
				description = "The " + brand + " " + noun + " offers " + pick(r, e.ref.Features) + ". " + pick(r, e.ref.Benefits)
			}
			if chance(r, .95) {
				weight = c.top.WeightGrams[0] + r.IntN(c.top.WeightGrams[1]-c.top.WeightGrams[0]+1)
			}
			p.row(i+1, c.id, fmt.Sprintf("%s-%s-%07d", c.top.Code, c.leaf.Code, i+1), brand+" "+pick(r, e.ref.Adjectives)+" "+noun, description, brand, money(price), money(cost), stock, productStatuses[status], weight, tags, e.attributes(r, c, brand), stamp(created), stamp(between(r, created, e.cfg.Now.Unix())))
		}
		return &batch{tables: []*copyTable{p, inv}}
	}, nil)
	if err != nil {
		return err
	}
	// A shuffled Zipf ranking gives hot products spread across physical pages.
	// DRAFTs are excluded; a tail is intentionally never sold, like the Python lab.
	for i, p := range e.products {
		if p.status != 3 {
			e.ranking = append(e.ranking, int32(i))
		}
	}
	r := e.rng(5, 0)
	r.Shuffle(len(e.ranking), func(i, j int) { e.ranking[i], e.ranking[j] = e.ranking[j], e.ranking[i] })
	minimum := 0
	if e.cfg.Orders > 0 {
		minimum = (e.cfg.Items + e.cfg.Orders - 1) / e.cfg.Orders
	}
	if minimum > len(e.ranking) {
		return fmt.Errorf("%d distinct items per order requested but only %d non-DRAFT products generated", minimum, len(e.ranking))
	}
	e.ranking = e.ranking[:max(1, minimum, len(e.ranking)*90/100)]
	return nil
}
