package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/google/uuid"
	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
)

func init() {
	register("idempotence-test", "send N unique records with short timeouts; count duplicates in the topic", cmdIdempotence)
	register("large-message", "produce a big record (-mode single) or split it into chunks (-mode chunked)", cmdLarge)
	register("sr-produce", "produce JSON with the Schema Registry wire format (magic byte + schema id)", cmdSRProduce)
}

// reqHook counts produce requests on the wire vs batches acknowledged.
type reqHook struct{ produceReqs, writeErrs, batches atomic.Int64 }

func (h *reqHook) OnBrokerWrite(_ kgo.BrokerMetadata, key int16, _ int, _, _ time.Duration, err error) {
	if key == 0 { // ProduceRequest
		h.produceReqs.Add(1)
		if err != nil {
			h.writeErrs.Add(1)
		}
	}
}
func (h *reqHook) OnProduceBatchWritten(kgo.BrokerMetadata, string, int32, kgo.ProduceBatchMetrics) {
	h.batches.Add(1)
}

func endOffsets(ctx context.Context, topic string) (map[int32]int64, error) {
	adm, cl, err := newAdmin()
	if err != nil {
		return nil, err
	}
	defer cl.Close()
	lo, err := adm.ListEndOffsets(ctx, topic)
	if err != nil {
		return nil, err
	}
	out := map[int32]int64{}
	lo.Each(func(o kadm.ListedOffset) { out[o.Partition] = o.Offset })
	return out, nil
}

// readSince reads every record produced after `from` and returns the values.
func readSince(ctx context.Context, topic string, from map[int32]int64, opts ...kgo.Opt) ([]*kgo.Record, error) {
	start := map[int32]kgo.Offset{}
	for p, o := range from {
		start[p] = kgo.NewOffset().At(o)
	}
	opts = append(opts, kgo.ConsumePartitions(map[string]map[int32]kgo.Offset{topic: start}), kgo.FetchMaxWait(300*time.Millisecond))
	cl, err := newClient(opts...)
	if err != nil {
		return nil, err
	}
	defer cl.Close()
	var out []*kgo.Record
	for {
		pctx, cancel := context.WithTimeout(ctx, 3*time.Second)
		f := cl.PollFetches(pctx)
		cancel()
		var ferr error
		f.EachError(func(_ string, _ int32, err error) {
			if !errors.Is(err, context.DeadlineExceeded) {
				ferr = err
			}
		})
		if ferr != nil {
			return out, ferr
		}
		if f.NumRecords() == 0 {
			return out, nil
		}
		out = append(out, f.Records()...)
	}
}

func cmdIdempotence(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("idempotence-test", flag.ExitOnError)
	topic := fs.String("topic", "idempotence-demo", "topic")
	n := fs.Int("records", 200, "unique records to send")
	idem := fs.Bool("idempotent", true, "enable.idempotence")
	timeout := fs.Duration("request-timeout", time.Second, "client side produce request timeout (short => timeouts under network delay)")
	retries := fs.Int("retries", 20, "record retries")
	_ = fs.Parse(args)

	before, err := endOffsets(ctx, *topic)
	if err != nil {
		return err
	}
	acks := "all"
	pc := kafka.ProducerConfig{Acks: acks, Idempotent: *idem, Compression: "none", Linger: 0, Partitioner: "sticky",
		RecordRetries: *retries, DeliveryTimeout: 2 * time.Minute, RequestTimeout: *timeout / 2}
	popts, err := pc.Opts()
	if err != nil {
		return err
	}
	hook := &reqHook{}
	popts = append(popts, kgo.RequestTimeoutOverhead(*timeout/2), kgo.WithHooks(hook), kgo.RetryBackoffFn(func(int) time.Duration { return 200 * time.Millisecond }))
	cl, err := newClient(popts...)
	if err != nil {
		return err
	}
	run := uuid.NewString()[:8]
	var wg sync.WaitGroup
	var failed atomic.Int64
	start := time.Now()
	for i := 0; i < *n; i++ {
		wg.Add(1)
		cl.Produce(ctx, &kgo.Record{Topic: *topic, Key: []byte("k"), Value: []byte(fmt.Sprintf("%s-%05d", run, i))}, func(_ *kgo.Record, err error) {
			if err != nil {
				failed.Add(1)
			}
			wg.Done()
		})
		time.Sleep(5 * time.Millisecond)
	}
	wg.Wait()
	cl.Close()
	elapsed := time.Since(start)

	recs, err := readSince(ctx, *topic, before)
	if err != nil {
		return err
	}
	counts := map[string]int{}
	for _, r := range recs {
		if strings.HasPrefix(string(r.Value), run) {
			counts[string(r.Value)]++
		}
	}
	total, dups := 0, 0
	for _, c := range counts {
		total += c
		if c > 1 {
			dups += c - 1
		}
	}
	fmt.Printf("idempotent=%t acks=%s sent=%d failed=%d elapsed=%s\n", *idem, acks, *n, failed.Load(), elapsed.Round(time.Millisecond))
	fmt.Printf("produce requests on the wire=%d (write errors=%d), batches acknowledged=%d\n",
		hook.produceReqs.Load(), hook.writeErrs.Load(), hook.batches.Load())
	fmt.Printf("records in topic for this run=%d distinct=%d DUPLICATES=%d\n", total, len(counts), dups)
	return nil
}

func parseSize(s string) (int, error) {
	s = strings.ToUpper(strings.TrimSpace(s))
	mult := 1
	switch {
	case strings.HasSuffix(s, "MB"):
		mult, s = 1<<20, strings.TrimSuffix(s, "MB")
	case strings.HasSuffix(s, "KB"):
		mult, s = 1<<10, strings.TrimSuffix(s, "KB")
	}
	f, err := strconv.ParseFloat(s, 64)
	return int(f * float64(mult)), err
}

func cmdLarge(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("large-message", flag.ExitOnError)
	topic := fs.String("topic", "large-messages", "topic")
	sizeS := fs.String("size", "2MB", "payload size")
	mode := fs.String("mode", "single", "single | chunked")
	chunkS := fs.String("chunk", "256KB", "chunk size (chunked mode)")
	clientMax := fs.String("client-max-batch", "1MB", "producer batch.max.bytes (franz-go rejects bigger records client side)")
	_ = fs.Parse(args)
	size, err := parseSize(*sizeS)
	if err != nil {
		return err
	}
	cmax, err := parseSize(*clientMax)
	if err != nil {
		return err
	}
	data := []byte(strings.Repeat("0123456789abcdef", size/16+1)[:size])
	sum := sha256.Sum256(data)

	cl, err := newClient(kgo.ProducerBatchMaxBytes(int32(cmax)), kgo.ProducerBatchCompression(kgo.NoCompression()))
	if err != nil {
		return err
	}
	defer cl.Close()

	if *mode == "single" {
		out, err := cl.ProduceSync(ctx, &kgo.Record{Topic: *topic, Key: []byte("blob-1"), Value: data}).First()
		if err != nil {
			fmt.Printf("single record of %d bytes FAILED: %v\n", size, err)
			return nil
		}
		fmt.Printf("single record of %d bytes OK: partition=%d offset=%d\n", size, out.Partition, out.Offset)
		return nil
	}

	chunk, err := parseSize(*chunkS)
	if err != nil {
		return err
	}
	before, err := endOffsets(ctx, *topic)
	if err != nil {
		return err
	}
	id := uuid.NewString()
	total := (size + chunk - 1) / chunk
	for i := 0; i < total; i++ {
		part := data[i*chunk : min((i+1)*chunk, size)]
		out, err := cl.ProduceSync(ctx, &kgo.Record{Topic: *topic, Key: []byte(id), Value: part, Headers: []kgo.RecordHeader{
			{Key: "chunk_id", Value: []byte(id)},
			{Key: "chunk_index", Value: []byte(strconv.Itoa(i))},
			{Key: "total_chunks", Value: []byte(strconv.Itoa(total))},
			{Key: "sha256", Value: []byte(hex.EncodeToString(sum[:]))},
		}}).First()
		if err != nil {
			return fmt.Errorf("chunk %d: %w", i, err)
		}
		fmt.Printf("chunk %2d/%d bytes=%d -> partition=%d offset=%d\n", i+1, total, len(part), out.Partition, out.Offset)
	}
	recs, err := readSince(ctx, *topic, before)
	if err != nil {
		return err
	}
	var got []*kgo.Record
	for _, r := range recs {
		if v, _ := kafka.Header(r, "chunk_id"); v == id {
			got = append(got, r)
		}
	}
	sort.Slice(got, func(i, j int) bool { return got[i].Offset < got[j].Offset })
	var buf bytes.Buffer
	for i, r := range got {
		idx, _ := strconv.Atoi(func() string { v, _ := kafka.Header(r, "chunk_index"); return v }())
		if idx != i {
			return fmt.Errorf("chunk order broken: expected %d got %d", i, idx)
		}
		buf.Write(r.Value)
	}
	re := sha256.Sum256(buf.Bytes())
	fmt.Printf("reassembled %d chunks, %d bytes, sha256 match=%t\n", len(got), buf.Len(), re == sum)
	return nil
}

func cmdSRProduce(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("sr-produce", flag.ExitOnError)
	registry := fs.String("registry", "http://schema-registry:8081", "Schema Registry URL")
	subject := fs.String("subject", "orders-sr-value", "subject")
	version := fs.String("version", "latest", "schema version")
	topic := fs.String("topic", "orders-sr", "topic")
	key := fs.String("key", "order-sr-1", "key")
	value := fs.String("value", `{"order_id":"order-sr-1","user_id":1,"product_id":2,"quantity":3}`, "JSON value")
	_ = fs.Parse(args)

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("%s/subjects/%s/versions/%s", *registry, *subject, *version), nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return fmt.Errorf("schema registry %d: %s", resp.StatusCode, body)
	}
	var sv struct {
		ID      int `json:"id"`
		Version int `json:"version"`
	}
	if err := json.Unmarshal(body, &sv); err != nil {
		return err
	}
	// Confluent wire format: [0x00 magic][4 byte big-endian schema id][payload]
	wire := make([]byte, 5, 5+len(*value))
	binary.BigEndian.PutUint32(wire[1:], uint32(sv.ID))
	wire = append(wire, []byte(*value)...)
	cl, err := newClient()
	if err != nil {
		return err
	}
	defer cl.Close()
	out, err := cl.ProduceSync(ctx, &kgo.Record{Topic: *topic, Key: []byte(*key), Value: wire}).First()
	if err != nil {
		return err
	}
	fmt.Printf("produced with schema id=%d (subject %s v%d): partition=%d offset=%d first bytes=% x\n",
		sv.ID, *subject, sv.Version, out.Partition, out.Offset, wire[:5])
	return nil
}
