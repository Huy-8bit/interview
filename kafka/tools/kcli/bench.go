package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"math/rand/v2"
	"os"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"text/tabwriter"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
)

func init() {
	register("bench-produce", "producer benchmark: acks / linger / batch / compression -> throughput, latency, bytes, CPU", cmdBenchProduce)
	register("bench-consume", "consumer benchmark: N consumers in one group with simulated per-record work", cmdBenchConsume)
}

// batchHook collects what actually went over the wire.
type batchHook struct {
	batches, records, uncompressed, compressed atomic.Int64
}

func (h *batchHook) OnProduceBatchWritten(_ kgo.BrokerMetadata, _ string, _ int32, m kgo.ProduceBatchMetrics) {
	h.batches.Add(1)
	h.records.Add(int64(m.NumRecords))
	h.uncompressed.Add(int64(m.UncompressedBytes))
	h.compressed.Add(int64(m.CompressedBytes))
}

var words = strings.Fields("order payment user product quantity created pending shipped warehouse inventory reserved " +
	"customer address hanoi saigon danang express standard priority invoice discount voucher total amount currency vnd")

// payload builds realistic (compressible) JSON or random (incompressible) bytes.
func payload(size int, kind string) []byte {
	if kind == "random" {
		b := make([]byte, size)
		for i := range b {
			b[i] = byte(rand.IntN(256))
		}
		return b
	}
	var sb strings.Builder
	for sb.Len() < size-120 {
		sb.WriteString(words[rand.IntN(len(words))])
		sb.WriteByte(' ')
	}
	m := map[string]any{"event_type": "OrderCreated", "order_id": fmt.Sprintf("order-%08d", rand.IntN(1e8)),
		"user_id": rand.IntN(100000), "product_id": rand.IntN(5000), "quantity": 1 + rand.IntN(5), "note": sb.String()}
	b, _ := json.Marshal(m)
	return b
}

func cpuTime() time.Duration {
	var ru syscall.Rusage
	_ = syscall.Getrusage(syscall.RUSAGE_SELF, &ru)
	return time.Duration(ru.Utime.Nano() + ru.Stime.Nano())
}

func pct(sorted []time.Duration, p float64) time.Duration {
	if len(sorted) == 0 {
		return 0
	}
	i := int(float64(len(sorted)-1) * p)
	return sorted[i]
}

func cmdBenchProduce(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("bench-produce", flag.ExitOnError)
	topic := fs.String("topic", "perf-p6", "topic")
	n := fs.Int("records", 100000, "records")
	size := fs.Int("size", 1024, "approx record size in bytes")
	kind := fs.String("payload", "json", "json (compressible) | random (incompressible)")
	acks := fs.String("acks", "all", "0|1|all")
	idem := fs.Bool("idempotent", true, "idempotent (only with acks=all)")
	comp := fs.String("compression", "none", "none|gzip|snappy|lz4|zstd")
	linger := fs.Duration("linger", 5*time.Millisecond, "linger")
	batch := fs.Int("batch-bytes", 1<<20, "max batch bytes per partition")
	keyed := fs.Bool("keyed", true, "random keys (spread over partitions); false = null key (sticky)")
	label := fs.String("label", "", "label printed in the result line")
	asJSON := fs.Bool("json", false, "print result as JSON")
	_ = fs.Parse(args)

	pc := kafka.ProducerConfig{Acks: *acks, Idempotent: *idem, Compression: *comp, Linger: *linger,
		BatchMaxBytes: int32(*batch), Partitioner: "sticky"}
	popts, err := pc.Opts()
	if err != nil {
		return err
	}
	hook := &batchHook{}
	popts = append(popts, kgo.WithHooks(hook), kgo.MaxBufferedRecords(20000))
	cl, err := newClient(popts...)
	if err != nil {
		return err
	}
	defer cl.Close()
	// warm up metadata + connections so they are not part of the measurement
	if err := cl.ProduceSync(ctx, &kgo.Record{Topic: *topic, Value: []byte("warmup")}).FirstErr(); err != nil {
		return err
	}
	hook.batches.Store(0)
	hook.records.Store(0)
	hook.uncompressed.Store(0)
	hook.compressed.Store(0)

	// pre-generate a pool of payloads so generation cost is not measured
	pool := make([][]byte, 256)
	for i := range pool {
		pool[i] = payload(*size, *kind)
	}
	lat := make([]time.Duration, *n)
	var errs atomic.Int64
	var wg sync.WaitGroup
	cpu0 := cpuTime()
	start := time.Now()
	for i := 0; i < *n; i++ {
		r := &kgo.Record{Topic: *topic, Value: pool[i%len(pool)]}
		if *keyed {
			r.Key = []byte(fmt.Sprintf("k-%d", rand.IntN(1_000_000)))
		}
		t0 := time.Now()
		idx := i
		wg.Add(1)
		cl.Produce(ctx, r, func(_ *kgo.Record, err error) {
			lat[idx] = time.Since(t0)
			if err != nil {
				errs.Add(1)
			}
			wg.Done()
		})
	}
	wg.Wait()
	elapsed := time.Since(start)
	cpu := cpuTime() - cpu0
	sort.Slice(lat, func(i, j int) bool { return lat[i] < lat[j] })

	var payloadBytes int64
	for i := 0; i < *n; i++ {
		payloadBytes += int64(len(pool[i%len(pool)]))
	}
	res := map[string]any{
		"label": *label, "topic": *topic, "records": *n, "errors": errs.Load(), "acks": *acks, "compression": *comp,
		"linger_ms": linger.Milliseconds(), "batch_bytes": *batch, "payload": *kind, "record_bytes": *size,
		"seconds": elapsed.Seconds(), "records_per_sec": float64(*n) / elapsed.Seconds(),
		"mb_per_sec": float64(payloadBytes) / elapsed.Seconds() / 1e6,
		"p50_ms":     ms(pct(lat, .50)), "p95_ms": ms(pct(lat, .95)), "p99_ms": ms(pct(lat, .99)), "max_ms": ms(lat[len(lat)-1]),
		"batches": hook.batches.Load(), "avg_records_per_batch": float64(hook.records.Load()) / max(1, float64(hook.batches.Load())),
		"wire_mb": float64(hook.compressed.Load()) / 1e6, "uncompressed_mb": float64(hook.uncompressed.Load()) / 1e6,
		"compression_ratio":  float64(hook.uncompressed.Load()) / max(1, float64(hook.compressed.Load())),
		"client_cpu_seconds": cpu.Seconds(),
	}
	if *asJSON {
		return json.NewEncoder(os.Stdout).Encode(res)
	}
	fmt.Printf("%-28s %9.0f rec/s %7.1f MB/s | p50 %7.2fms p99 %8.2fms | batches %6d (%5.0f rec/batch) | wire %7.1fMB ratio %4.2f | cpu %5.2fs | errors %d\n",
		strOr(*label, fmt.Sprintf("acks=%s comp=%s linger=%s", *acks, *comp, *linger)),
		res["records_per_sec"], res["mb_per_sec"], res["p50_ms"], res["p99_ms"], res["batches"], res["avg_records_per_batch"],
		res["wire_mb"], res["compression_ratio"], cpu.Seconds(), errs.Load())
	return nil
}

func ms(d time.Duration) float64 { return float64(d.Microseconds()) / 1000 }

func strOr(a, b string) string {
	if a != "" {
		return a
	}
	return b
}

func cmdBenchConsume(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("bench-consume", flag.ExitOnError)
	topic := fs.String("topic", "perf-p6", "topic")
	consumers := fs.Int("consumers", 1, "consumer instances in the group")
	records := fs.Int("records", 20000, "stop after this many records in total")
	work := fs.Duration("work", time.Millisecond, "simulated processing time per record")
	group := fs.String("group", "", "group id (default bench-<random>)")
	label := fs.String("label", "", "label printed in the result line")
	verbose := fs.Bool("v", false, "print per consumer stats")
	_ = fs.Parse(args)
	if *group == "" {
		*group = fmt.Sprintf("bench-%d", time.Now().UnixNano()%1e9)
	}

	var (
		total   atomic.Int64
		first   atomic.Int64
		doneCh  = make(chan struct{})
		once    sync.Once
		wg      sync.WaitGroup
		mu      sync.Mutex
		perCons = make([]int64, *consumers)
		parts   = make([]map[int32]bool, *consumers)
	)
	cctx, cancel := context.WithCancel(ctx)
	defer cancel()
	for i := 0; i < *consumers; i++ {
		parts[i] = map[int32]bool{}
		cl, err := newClient(
			kgo.ClientID(fmt.Sprintf("bench-consumer-%d", i+1)),
			kgo.ConsumerGroup(*group), kgo.ConsumeTopics(*topic),
			kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()),
			kgo.DisableAutoCommit(), kgo.Balancers(kgo.CooperativeStickyBalancer()),
			kgo.FetchMaxWait(200*time.Millisecond),
		)
		if err != nil {
			return err
		}
		wg.Add(1)
		go func(i int, cl *kgo.Client) {
			defer wg.Done()
			defer cl.Close()
			for {
				f := cl.PollRecords(cctx, 200)
				if cctx.Err() != nil {
					return
				}
				f.EachRecord(func(r *kgo.Record) {
					first.CompareAndSwap(0, time.Now().UnixNano())
					if *work > 0 {
						time.Sleep(*work)
					}
					mu.Lock()
					perCons[i]++
					parts[i][r.Partition] = true
					mu.Unlock()
					if total.Add(1) >= int64(*records) {
						once.Do(func() { close(doneCh) })
					}
				})
			}
		}(i, cl)
	}
	select {
	case <-doneCh:
	case <-time.After(10 * time.Minute):
		fmt.Println("timeout")
	case <-ctx.Done():
	}
	end := time.Now()
	cancel()
	wg.Wait()
	elapsed := end.Sub(time.Unix(0, first.Load()))
	active := 0
	for _, c := range perCons {
		if c > 0 {
			active++
		}
	}
	fmt.Printf("%-24s consumers=%d active=%d records=%d time=%6.2fs throughput=%8.0f rec/s (work=%s/record)\n",
		strOr(*label, *topic), *consumers, active, total.Load(), elapsed.Seconds(), float64(total.Load())/elapsed.Seconds(), *work)
	if *verbose {
		w := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
		for i := range perCons {
			var ps []string
			for p := range parts[i] {
				ps = append(ps, fmt.Sprintf("P%d", p))
			}
			sort.Strings(ps)
			state := ""
			if perCons[i] == 0 {
				state = "IDLE (no partition)"
			}
			fmt.Fprintf(w, "    bench-consumer-%d\trecords=%d\tpartitions=%s\t%s\n", i+1, perCons[i], strings.Join(ps, ","), state)
		}
		_ = w.Flush()
	}
	// clean up the throwaway group
	adm, cl, err := newAdmin()
	if err == nil {
		dctx, c := withTimeout(context.Background(), 5*time.Second)
		_, _ = adm.DeleteGroups(dctx, *group)
		c()
		cl.Close()
	}
	return nil
}
