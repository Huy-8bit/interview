package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"
)

// COPY text is encoded once per batch, avoiding a driver call and Python object
// conversion per row. Money never goes through a floating point representation.
type copyTable struct {
	name, columns string
	data          bytes.Buffer
	rows          int64
}
type money int64
type null struct{}

var nilValue = null{}
var copyEscape = strings.NewReplacer("\\", "\\\\", "\t", "\\t", "\n", "\\n", "\r", "\\r")

func (t *copyTable) row(values ...any) {
	for i, v := range values {
		if i > 0 {
			t.data.WriteByte('\t')
		}
		switch x := v.(type) {
		case null, nil:
			t.data.WriteString(`\N`)
		case string:
			t.data.WriteString(copyEscape.Replace(x))
		case []string:
			var b strings.Builder
			b.WriteByte('{')
			for j, s := range x {
				if j > 0 {
					b.WriteByte(',')
				}
				b.WriteByte('"')
				b.WriteString(strings.NewReplacer("\\", "\\\\", "\"", "\\\"").Replace(s))
				b.WriteByte('"')
			}
			b.WriteByte('}')
			t.data.WriteString(copyEscape.Replace(b.String()))
		case int:
			t.data.WriteString(strconv.Itoa(x))
		case int64:
			t.data.WriteString(strconv.FormatInt(x, 10))
		case int32:
			t.data.WriteString(strconv.FormatInt(int64(x), 10))
		case bool:
			if x {
				t.data.WriteByte('t')
			} else {
				t.data.WriteByte('f')
			}
		case money:
			n := int64(x)
			if n < 0 {
				t.data.WriteByte('-')
				n = -n
			}
			t.data.WriteString(strconv.FormatInt(n/100, 10))
			t.data.WriteByte('.')
			t.data.WriteByte(byte(n%100/10) + '0')
			t.data.WriteByte(byte(n%10) + '0')
		case time.Time:
			t.data.WriteString(x.UTC().Format(time.RFC3339Nano))
		default:
			panic(fmt.Sprintf("unsupported COPY value %T", v))
		}
	}
	t.data.WriteByte('\n')
	t.rows++
}
func jsonText(v any) string {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return string(b)
}

type batch struct {
	tables    []*copyTable
	purchases []purchase
}
type sink interface {
	Write(context.Context, *batch) error
}
type discardSink struct{}

func (discardSink) Write(ctx context.Context, b *batch) error { return ctx.Err() }

// At most Workers batches are buffered; writes stay in ID order regardless of
// scheduling. Each worker owns its RNG and buffers, so there are no data races.
func (e *engine) batches(ctx context.Context, label string, n int, build func(int, int) *batch, after func(*batch)) error {
	started := time.Now()
	for start := 0; start < n; {
		if err := ctx.Err(); err != nil {
			return err
		}
		count := min(e.cfg.Workers, (n-start+e.cfg.Batch-1)/e.cfg.Batch)
		results := make([]*batch, count)
		var wg sync.WaitGroup
		for w := 0; w < count; w++ {
			lo := start + w*e.cfg.Batch
			hi := min(lo+e.cfg.Batch, n)
			wg.Add(1)
			go func(w, lo, hi int) { defer wg.Done(); results[w] = build(lo, hi) }(w, lo, hi)
		}
		wg.Wait()
		for _, b := range results {
			if err := e.sink.Write(ctx, b); err != nil {
				return err
			}
			for _, t := range b.tables {
				e.counts[t.name] += t.rows
				e.bytes += int64(t.data.Len())
			}
			if after != nil {
				after(b)
			}
		}
		start = min(start+count*e.cfg.Batch, n)
		fmt.Fprintf(e.log, "  %s: %d / %d (%.0f parent rows/s)\n", label, start, n, float64(start)/time.Since(started).Seconds())
	}
	return nil
}
