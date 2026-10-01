package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/events"
	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
)

func init() {
	register("produce", "produce raw records (-count N, -null-value for tombstones, -acks, -compression)", cmdProduce)
	register("order", "produce one OrderCreated JSON event (-fault, -quantity, -product ...)", cmdOrder)
	register("consume", "print records with partition/offset/key/headers (-group, -from, -isolation)", cmdConsume)
}

type headerFlags []string

func (h *headerFlags) String() string     { return strings.Join(*h, ",") }
func (h *headerFlags) Set(v string) error { *h = append(*h, v); return nil }

func cmdProduce(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("produce", flag.ExitOnError)
	topic := fs.String("topic", "orders", "topic")
	key := fs.String("key", "", "record key (empty = null key)")
	value := fs.String("value", "hello", "record value; {i} is replaced by the record index")
	nullValue := fs.Bool("null-value", false, "send a null value (tombstone)")
	count := fs.Int("count", 1, "records to send")
	acks := fs.String("acks", "all", "0|1|all")
	idem := fs.Bool("idempotent", true, "idempotent producer (needs acks=all)")
	compression := fs.String("compression", "none", "none|gzip|snappy|lz4|zstd")
	partition := fs.Int("partition", -1, "force a partition (manual partitioner)")
	timeout := fs.Duration("timeout", 0, "delivery timeout: give up retrying after this long (0 = client default)")
	quiet := fs.Bool("quiet", false, "only print a summary")
	async := fs.Bool("async", false, "produce everything asynchronously then flush (shows batching / sticky partitioning)")
	var headers headerFlags
	fs.Var(&headers, "header", "k=v header (repeatable)")
	_ = fs.Parse(args)

	pc := kafka.ProducerConfig{Acks: *acks, Idempotent: *idem, Compression: *compression, Linger: 5 * time.Millisecond, Partitioner: "sticky",
		RecordRetries: -1, DeliveryTimeout: *timeout}
	popts, err := pc.Opts()
	if err != nil {
		return err
	}
	if *partition >= 0 {
		popts = append(popts, kgo.RecordPartitioner(kgo.ManualPartitioner()))
	}
	hook := &batchHook{}
	popts = append(popts, kgo.WithHooks(hook))
	cl, err := newClient(popts...)
	if err != nil {
		return err
	}
	defer cl.Close()
	perPartition := map[int32]int{}
	var mu sync.Mutex
	start := time.Now()
	for i := 0; i < *count; i++ {
		r := &kgo.Record{Topic: *topic}
		if *key != "" {
			r.Key = []byte(strings.ReplaceAll(*key, "{i}", strconv.Itoa(i)))
		}
		if !*nullValue {
			r.Value = []byte(strings.ReplaceAll(*value, "{i}", strconv.Itoa(i)))
		}
		if *partition >= 0 {
			r.Partition = int32(*partition)
		}
		for _, h := range headers {
			k, v, _ := strings.Cut(h, "=")
			r.Headers = append(r.Headers, kgo.RecordHeader{Key: k, Value: []byte(v)})
		}
		if *async {
			cl.Produce(ctx, r, func(out *kgo.Record, err error) {
				if err == nil {
					mu.Lock()
					perPartition[out.Partition]++
					mu.Unlock()
				}
			})
			continue
		}
		out, err := cl.ProduceSync(ctx, r).First()
		if err != nil {
			return fmt.Errorf("record %d: %w", i, err)
		}
		perPartition[out.Partition]++
		if !*quiet {
			v := "null"
			if out.Value != nil {
				v = trunc(string(out.Value), 80)
			}
			fmt.Printf("produced topic=%s partition=%d offset=%d key=%s value=%s\n", out.Topic, out.Partition, out.Offset, string(out.Key), v)
		}
	}
	if err := cl.Flush(ctx); err != nil {
		return err
	}
	fmt.Printf("sent %d record(s) in %s (%d produce batches), per partition: %v\n", *count, time.Since(start).Round(time.Millisecond), hook.batches.Load(), perPartition)
	return nil
}

func cmdOrder(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("order", flag.ExitOnError)
	topic := fs.String("topic", "orders", "topic")
	user := fs.Int64("user", 1001, "user_id")
	product := fs.Int64("product", 500, "product_id")
	qty := fs.Int("quantity", 2, "quantity (negative = poison)")
	orderID := fs.String("order-id", "", "order id (default random)")
	fault := fs.String("fault", "", "lab_fault: crash_after_process|crash_before_process|abort_txn|slow")
	count := fs.Int("count", 1, "number of orders")
	_ = fs.Parse(args)
	cl, err := newClient()
	if err != nil {
		return err
	}
	defer cl.Close()
	for i := 0; i < *count; i++ {
		ev := events.NewOrderCreated(*user, *product, *qty)
		if *orderID != "" {
			ev.OrderID = *orderID
			if *count > 1 {
				ev.OrderID = fmt.Sprintf("%s-%d", *orderID, i)
			}
		}
		ev.LabFault = *fault
		val, _ := json.Marshal(ev)
		out, err := cl.ProduceSync(ctx, &kgo.Record{Topic: *topic, Key: []byte(ev.OrderID), Value: val, Headers: []kgo.RecordHeader{
			{Key: events.HeaderEventType, Value: []byte(ev.EventType)},
			{Key: events.HeaderProducer, Value: []byte("kcli")},
		}}).First()
		if err != nil {
			return err
		}
		fmt.Printf("produced topic=%s partition=%d offset=%d key=%s event_id=%s quantity=%d fault=%s\n",
			out.Topic, out.Partition, out.Offset, ev.OrderID, ev.EventID, ev.Quantity, ev.LabFault)
	}
	return nil
}

func cmdConsume(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("consume", flag.ExitOnError)
	topic := fs.String("topic", "orders", "topic(s), comma separated")
	group := fs.String("group", "", "consumer group (empty = no group, nothing committed)")
	from := fs.String("from", "start", "start|end|<offset> (no group or new group)")
	partition := fs.Int("partition", -1, "only this partition (no group)")
	maxN := fs.Int("max", 0, "stop after N records (0 = until idle)")
	idle := fs.Duration("idle", 3*time.Second, "stop when no record arrives for this long")
	isolation := fs.String("isolation", "uncommitted", "committed|uncommitted (read_committed hides aborted txn records)")
	showHeaders := fs.Bool("headers", false, "print headers")
	maxValue := fs.Int("max-value", 160, "truncate printed values")
	summary := fs.Bool("summary", false, "only print counts (per partition, distinct values)")
	_ = fs.Parse(args)

	var off kgo.Offset
	switch *from {
	case "start":
		off = kgo.NewOffset().AtStart()
	case "end":
		off = kgo.NewOffset().AtEnd()
	default:
		n, err := strconv.ParseInt(*from, 10, 64)
		if err != nil {
			return errors.New("-from must be start|end|<offset>")
		}
		off = kgo.NewOffset().At(n)
	}
	topics := strings.Split(*topic, ",")
	opts := []kgo.Opt{kgo.FetchMaxWait(300 * time.Millisecond)}
	if *isolation == "committed" {
		opts = append(opts, kgo.FetchIsolationLevel(kgo.ReadCommitted()))
	}
	switch {
	case *group != "":
		opts = append(opts, kgo.ConsumerGroup(*group), kgo.ConsumeTopics(topics...), kgo.ConsumeResetOffset(off))
	case *partition >= 0:
		opts = append(opts, kgo.ConsumePartitions(map[string]map[int32]kgo.Offset{topics[0]: {int32(*partition): off}}))
	default:
		opts = append(opts, kgo.ConsumeTopics(topics...), kgo.ConsumeResetOffset(off))
	}
	cl, err := newClient(opts...)
	if err != nil {
		return err
	}
	defer cl.Close()

	n := 0
	perPartition := map[string]int{}
	values := map[string]int{}
	for {
		pctx, cancel := context.WithTimeout(ctx, *idle)
		fetches := cl.PollFetches(pctx)
		cancel()
		if ctx.Err() != nil {
			break
		}
		var fetchErr error
		fetches.EachError(func(t string, p int32, err error) {
			if !errors.Is(err, context.DeadlineExceeded) {
				fetchErr = fmt.Errorf("%s[%d]: %w", t, p, err)
			}
		})
		if fetchErr != nil {
			return fetchErr
		}
		if fetches.NumRecords() == 0 {
			break // idle
		}
		done := false
		fetches.EachRecord(func(r *kgo.Record) {
			if done {
				return
			}
			n++
			perPartition[fmt.Sprintf("%s/P%d", r.Topic, r.Partition)]++
			values[string(r.Value)]++
			if !*summary {
				v := "null"
				if r.Value != nil {
					v = trunc(string(r.Value), *maxValue)
				}
				fmt.Printf("%s P%d @%-6d key=%-20s ts=%s value=%s\n", r.Topic, r.Partition, r.Offset, string(r.Key),
					r.Timestamp.Format("15:04:05.000"), v)
				if *showHeaders && len(r.Headers) > 0 {
					for _, h := range r.Headers {
						fmt.Printf("      header %s=%s\n", h.Key, trunc(string(h.Value), 200))
					}
				}
			}
			if *maxN > 0 && n >= *maxN {
				done = true
			}
		})
		if done {
			break
		}
	}
	if *group != "" {
		cctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		_ = cl.CommitUncommittedOffsets(cctx)
		cancel()
	}
	keys := make([]string, 0, len(perPartition))
	for k := range perPartition {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	dups := 0
	for _, c := range values {
		if c > 1 {
			dups += c - 1
		}
	}
	fmt.Printf("-- %d record(s), %d distinct value(s), %d duplicate value(s); per partition:", n, len(values), dups)
	for _, k := range keys {
		fmt.Printf(" %s=%d", k, perPartition[k])
	}
	fmt.Println()
	return nil
}

func trunc(s string, n int) string {
	if n > 0 && len(s) > n {
		return s[:n] + "…"
	}
	return s
}
