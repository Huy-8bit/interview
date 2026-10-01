package main

import (
	"context"
	"flag"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"
)

func init() {
	register("ordering-test", "produce N events for K keys (and without key), read back, verify ordering", cmdOrdering)
}

// cmdOrdering:
//  1. snapshot end offsets of the topic
//  2. produce `events` sequenced records for each of `keys` keys, ASYNC (many in flight),
//     interleaving keys: order-0 #1, order-1 #1, order-2 #1, order-0 #2 ...
//  3. read everything after the snapshot and check, per key, that sequence numbers
//     come back strictly increasing, and print where each key landed.
//  4. with -nokey the same records are sent with a null key: they spread over
//     partitions and per-"order" ordering is no longer guaranteed.
func cmdOrdering(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("ordering-test", flag.ExitOnError)
	topic := fs.String("topic", "ordering-demo", "topic (6 partitions)")
	keys := fs.Int("keys", 3, "number of distinct order keys")
	evs := fs.Int("events", 5, "events per key")
	nokey := fs.Bool("nokey", false, "send WITHOUT key (null key)")
	partitioner := fs.String("partitioner", "sticky", "sticky|roundrobin (only matters for -nokey)")
	_ = fs.Parse(args)

	adm, admCl, err := newAdmin()
	if err != nil {
		return err
	}
	defer admCl.Close()
	before, err := adm.ListEndOffsets(ctx, *topic)
	if err != nil {
		return err
	}

	popts := []kgo.Opt{kgo.ProducerLinger(20 * time.Millisecond)}
	if *partitioner == "roundrobin" {
		popts = append(popts, kgo.RecordPartitioner(kgo.RoundRobinPartitioner()))
	}
	cl, err := newClient(popts...)
	if err != nil {
		return err
	}
	defer cl.Close()

	runID := strconv.FormatInt(time.Now().UnixMilli()%100000, 10)
	var wg sync.WaitGroup
	for seq := 1; seq <= *evs; seq++ {
		for k := 0; k < *keys; k++ {
			order := fmt.Sprintf("order-%s-%d", runID, k)
			r := &kgo.Record{Topic: *topic, Value: []byte(fmt.Sprintf("%s seq=%d", order, seq))}
			if !*nokey {
				r.Key = []byte(order)
			}
			wg.Add(1)
			cl.Produce(ctx, r, func(_ *kgo.Record, err error) {
				defer wg.Done()
				if err != nil {
					fmt.Println("produce error:", err)
				}
			})
		}
	}
	wg.Wait()
	mode := "key = order id"
	if *nokey {
		mode = "NO key (null) partitioner=" + *partitioner
	}
	fmt.Printf("produced %d keys x %d events, %s, run=%s (async, interleaved)\n\n", *keys, *evs, mode, runID)

	start := map[int32]kgo.Offset{}
	before.Each(func(o kadm.ListedOffset) { start[o.Partition] = kgo.NewOffset().At(o.Offset) })
	rc, err := newClient(kgo.ConsumePartitions(map[string]map[int32]kgo.Offset{*topic: start}), kgo.FetchMaxWait(300*time.Millisecond))
	if err != nil {
		return err
	}
	defer rc.Close()

	type seen struct {
		seq       int
		partition int32
		offset    int64
	}
	byOrder := map[string][]seen{}
	var global []string // in the order this single consumer received them
	want := *keys * *evs
	got := 0
	deadline := time.Now().Add(20 * time.Second)
	for got < want && time.Now().Before(deadline) {
		pctx, cancel := context.WithTimeout(ctx, 2*time.Second)
		f := rc.PollFetches(pctx)
		cancel()
		f.EachRecord(func(r *kgo.Record) {
			v := string(r.Value)
			if !strings.Contains(v, "-"+runID+"-") {
				return
			}
			order, seqS, _ := strings.Cut(v, " seq=")
			seq, _ := strconv.Atoi(seqS)
			byOrder[order] = append(byOrder[order], seen{seq, r.Partition, r.Offset})
			global = append(global, fmt.Sprintf("%s#%d", order[len(order)-1:], seq))
			got++
		})
	}

	orders := make([]string, 0, len(byOrder))
	for o := range byOrder {
		orders = append(orders, o)
	}
	sort.Strings(orders)
	allOrdered := true
	for _, o := range orders {
		ss := byOrder[o]
		parts := map[int32]bool{}
		var seqs []string
		ordered := true
		for i, s := range ss {
			parts[s.partition] = true
			seqs = append(seqs, fmt.Sprintf("%d(P%d@%d)", s.seq, s.partition, s.offset))
			if i > 0 && s.seq < ss[i-1].seq {
				ordered = false
			}
		}
		allOrdered = allOrdered && ordered
		var pl []string
		for p := range parts {
			pl = append(pl, fmt.Sprintf("P%d", p))
		}
		sort.Strings(pl)
		verdict := "IN ORDER"
		if !ordered {
			verdict = "OUT OF ORDER"
		}
		fmt.Printf("%-20s partitions=%-18s %-12s seq: %s\n", o, strings.Join(pl, ","), verdict, strings.Join(seqs, " "))
	}
	fmt.Printf("\nconsumer receive order (key-suffix#seq): %s\n", strings.Join(global, " "))
	fmt.Printf("\nreceived %d/%d. ", got, want)
	if allOrdered {
		fmt.Println("Every key was consumed in production order.")
	} else {
		fmt.Println("At least one key was consumed OUT of production order.")
	}
	return nil
}
