// producer-service: HTTP API that turns requests into Kafka events.
//
//	POST /orders                       create an order -> OrderCreated on `orders`
//	     ?mode=sync|async              sync waits for the broker ack, async returns 202 immediately
//	     ?acks=0|1|all                 per-request acks (separate client per acks value)
//	     ?key=order_id|user_id|none    which field becomes the record key (-> partition)
//	POST /orders/{order_id}/events?count=5   OrderUpdated seq 1..N with the same key (ordering lab)
//	POST /orders/bulk?count=1000&mode=async  N random orders, returns per-partition counts
//	POST /raw?topic=orders&key=k             produce the raw request body (poison / malformed JSON)
//	PUT  /users/{id}/profile                 UserProfileUpdated -> user-events + user-profile-compacted
//	DELETE /users/{id}/profile               tombstone (value=null) on user-profile-compacted
//	GET  /config                             effective producer configuration
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"os"
	"sort"
	"strconv"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/app"
	"github.com/nghuy8bit/kafka-lab/pkg/config"
	"github.com/nghuy8bit/kafka-lab/pkg/events"
	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
	"github.com/nghuy8bit/kafka-lab/pkg/logging"
	"github.com/nghuy8bit/kafka-lab/pkg/metrics"
)

const service = "producer-service"

type server struct {
	log  *slog.Logger
	base kafka.ProducerConfig

	mu      sync.Mutex
	clients map[string]*kgo.Client // by acks value
}

func main() {
	log := logging.New(service)
	ctx, stop := app.SignalContext()
	defer stop()

	s := &server{log: log, base: kafka.ProducerConfigFromEnv(), clients: map[string]*kgo.Client{}}
	def, err := s.client(s.base.Acks)
	if err != nil {
		log.Error("cannot create producer", "err", err)
		os.Exit(1)
	}
	log.Info("producer ready", "config", s.base.String(), "brokers", config.Brokers())

	srv := metrics.NewServer(config.String("HTTP_ADDR", ":8080"))
	srv.SetHealth(func() error {
		hctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		return def.Ping(hctx)
	})
	srv.Handle("POST /orders", s.createOrder)
	srv.Handle("POST /orders/bulk", s.bulk)
	srv.Handle("POST /orders/{id}/events", s.orderEvents)
	srv.Handle("POST /raw", s.raw)
	srv.Handle("PUT /users/{id}/profile", s.putProfile)
	srv.Handle("DELETE /users/{id}/profile", s.deleteProfile)
	srv.Handle("GET /config", func(w http.ResponseWriter, r *http.Request) {
		metrics.WriteJSON(w, 200, map[string]any{"producer": s.base, "summary": s.base.String()})
	})
	srv.Start(log)

	<-ctx.Done()
	log.Info("shutdown: flushing buffered records")
	sctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	_ = srv.Shutdown(sctx)
	s.mu.Lock()
	for acks, cl := range s.clients {
		if err := cl.Flush(sctx); err != nil {
			log.Error("flush failed", "acks", acks, "err", err)
		}
		cl.Close()
	}
	s.mu.Unlock()
	log.Info("shutdown complete")
}

// client returns (lazily creating) a producer client for an acks value.
// acks is a client level setting in Kafka, so per-request acks needs separate clients.
func (s *server) client(acks string) (*kgo.Client, error) {
	if acks == "" {
		acks = s.base.Acks
	}
	if _, err := kafka.ParseAcks(acks); err != nil {
		return nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if cl, ok := s.clients[acks]; ok {
		return cl, nil
	}
	pc := s.base
	pc.Acks = acks
	cl, err := kafka.NewProducer(fmt.Sprintf("%s-acks-%s", service, acks), pc, s.log)
	if err != nil {
		return nil, err
	}
	s.clients[acks] = cl
	return cl, nil
}

type orderRequest struct {
	OrderID   string `json:"order_id"`
	UserID    int64  `json:"user_id"`
	ProductID int64  `json:"product_id"`
	Quantity  int    `json:"quantity"`
	LabFault  string `json:"lab_fault"`
}

type produceResult struct {
	EventID   string  `json:"event_id"`
	OrderID   string  `json:"order_id,omitempty"`
	Topic     string  `json:"topic"`
	Key       string  `json:"key"`
	Partition int32   `json:"partition"`
	Offset    int64   `json:"offset"`
	Acks      string  `json:"acks"`
	Mode      string  `json:"mode"`
	LatencyMs float64 `json:"latency_ms"`
	Sequence  int     `json:"sequence,omitempty"`
}

func keyFor(strategy string, ev events.OrderEvent) []byte {
	switch strategy {
	case "user_id":
		return []byte("user-" + strconv.FormatInt(ev.UserID, 10))
	case "none":
		return nil
	default:
		return []byte(ev.OrderID)
	}
}

func orderRecord(ev events.OrderEvent, key []byte) *kgo.Record {
	val, _ := json.Marshal(ev)
	return &kgo.Record{
		Topic: "orders",
		Key:   key,
		Value: val,
		Headers: []kgo.RecordHeader{
			{Key: events.HeaderEventType, Value: []byte(ev.EventType)},
			{Key: events.HeaderSchemaVersion, Value: []byte(strconv.Itoa(ev.SchemaVersion))},
			{Key: events.HeaderProducer, Value: []byte(service)},
		},
	}
}

func (s *server) createOrder(w http.ResponseWriter, r *http.Request) {
	var req orderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		metrics.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	// NOTE: the API deliberately does NOT validate quantity: the poison-message
	// lab needs invalid events to reach Kafka. A real API would reject them here.
	ev := events.NewOrderCreated(req.UserID, req.ProductID, req.Quantity)
	if req.OrderID != "" {
		ev.OrderID = req.OrderID
	}
	ev.LabFault = req.LabFault
	q := r.URL.Query()
	mode := orDefault(q.Get("mode"), "sync")
	acks := orDefault(q.Get("acks"), s.base.Acks)
	rec := orderRecord(ev, keyFor(q.Get("key"), ev))
	res, err := s.produce(r.Context(), rec, acks, mode)
	if err != nil {
		metrics.WriteJSON(w, http.StatusServiceUnavailable, map[string]any{"error": err.Error(), "event_id": ev.EventID})
		return
	}
	res.EventID, res.OrderID = ev.EventID, ev.OrderID
	status := http.StatusCreated
	if mode == "async" {
		status = http.StatusAccepted
	}
	metrics.WriteJSON(w, status, res)
}

// produce sends rec in sync or async mode and logs topic/partition/offset/key.
func (s *server) produce(ctx context.Context, rec *kgo.Record, acks, mode string) (produceResult, error) {
	cl, err := s.client(acks)
	if err != nil {
		return produceResult{}, err
	}
	res := produceResult{Topic: rec.Topic, Key: string(rec.Key), Acks: acks, Mode: mode, Partition: -1, Offset: -1}
	start := time.Now()
	if mode == "async" {
		// The request returns before the broker acks. Errors surface only in the
		// callback -> the caller never learns about them (fire-and-forget risk).
		kafka.ProduceAsync(context.Background(), cl, service, rec, func(r *kgo.Record, err error) {
			if err != nil {
				s.log.Error("async produce failed", "topic", r.Topic, "key", string(r.Key), "err", err)
				return
			}
			s.log.Info("produced (async ack)", "topic", r.Topic, "partition", r.Partition, "offset", r.Offset,
				"key", string(r.Key), "acks", acks, "latency", time.Since(start))
		})
		return res, nil
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	out, err := kafka.ProduceSync(ctx, cl, service, rec)
	res.LatencyMs = float64(time.Since(start).Microseconds()) / 1000
	if err != nil {
		s.log.Error("produce failed", "topic", rec.Topic, "key", string(rec.Key), "acks", acks, "err", err)
		return res, err
	}
	res.Partition, res.Offset = out.Partition, out.Offset
	if acks == "0" {
		// acks=0: the broker sends NO response, so the offset is unknown (-1).
		// "success" only means the bytes were written to the socket.
		res.Offset = -1
	}
	s.log.Info("produced", "topic", out.Topic, "partition", out.Partition, "offset", out.Offset,
		"key", string(out.Key), "acks", acks, "latency", time.Since(start))
	return res, nil
}

// orderEvents produces OrderUpdated sequence 1..count for ONE order id.
// With key=order_id they all land in the same partition => consumed in order.
func (s *server) orderEvents(w http.ResponseWriter, r *http.Request) {
	orderID := r.PathValue("id")
	q := r.URL.Query()
	count, _ := strconv.Atoi(orDefault(q.Get("count"), "3"))
	keyStrategy := q.Get("key")
	topic := orDefault(q.Get("topic"), "orders")
	cl, err := s.client(s.base.Acks)
	if err != nil {
		metrics.WriteJSON(w, 500, map[string]string{"error": err.Error()})
		return
	}
	var (
		wg      sync.WaitGroup
		mu      sync.Mutex
		results = make([]produceResult, count)
		errs    []string
	)
	for i := 1; i <= count; i++ {
		ev := events.OrderEvent{
			EventID: uuid.NewString(), EventType: events.OrderUpdated, SchemaVersion: 1,
			OrderID: orderID, UserID: 1001, ProductID: 500, Quantity: 1,
			Status: fmt.Sprintf("STEP-%d", i), Sequence: i, CreatedAt: time.Now().UTC(),
		}
		rec := orderRecord(ev, keyFor(keyStrategy, ev))
		rec.Topic = topic
		if keyStrategy == "" || keyStrategy == "order_id" {
			rec.Key = []byte(orderID)
		}
		wg.Add(1)
		idx := i - 1
		// async on purpose: many in-flight records, ordering still holds per partition
		kafka.ProduceAsync(r.Context(), cl, service, rec, func(out *kgo.Record, err error) {
			defer wg.Done()
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				errs = append(errs, err.Error())
				return
			}
			results[idx] = produceResult{EventID: ev.EventID, Topic: out.Topic, Key: string(out.Key),
				Partition: out.Partition, Offset: out.Offset, Sequence: ev.Sequence}
		})
	}
	wg.Wait()
	for _, res := range results {
		s.log.Info("produced", "topic", res.Topic, "partition", res.Partition, "offset", res.Offset,
			"key", res.Key, "sequence", res.Sequence)
	}
	metrics.WriteJSON(w, 200, map[string]any{"order_id": orderID, "results": results, "errors": errs})
}

func (s *server) bulk(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	count, _ := strconv.Atoi(orDefault(q.Get("count"), "100"))
	keyStrategy := q.Get("key")
	cl, err := s.client(orDefault(q.Get("acks"), s.base.Acks))
	if err != nil {
		metrics.WriteJSON(w, 400, map[string]string{"error": err.Error()})
		return
	}
	var (
		wg     sync.WaitGroup
		mu     sync.Mutex
		perP   = map[int32]int{}
		failed int
	)
	start := time.Now()
	for i := 0; i < count; i++ {
		ev := events.NewOrderCreated(int64(1000+rand.IntN(9000)), int64(1+rand.IntN(1000)), 1+rand.IntN(5))
		wg.Add(1)
		kafka.ProduceAsync(r.Context(), cl, service, orderRecord(ev, keyFor(keyStrategy, ev)), func(out *kgo.Record, err error) {
			defer wg.Done()
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				failed++
				return
			}
			perP[out.Partition]++
		})
	}
	wg.Wait()
	elapsed := time.Since(start)
	parts := make([]int, 0, len(perP))
	for p := range perP {
		parts = append(parts, int(p))
	}
	sort.Ints(parts)
	dist := make([]map[string]int, 0, len(parts))
	for _, p := range parts {
		dist = append(dist, map[string]int{"partition": p, "records": perP[int32(p)]})
	}
	s.log.Info("bulk produced", "count", count, "failed", failed, "elapsed", elapsed)
	metrics.WriteJSON(w, 200, map[string]any{
		"count": count, "failed": failed, "elapsed_ms": elapsed.Milliseconds(),
		"records_per_sec": float64(count) / elapsed.Seconds(), "per_partition": dist,
	})
}

func (s *server) raw(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	topic := orDefault(q.Get("topic"), "orders")
	body, err := io.ReadAll(io.LimitReader(r.Body, 16<<20))
	if err != nil {
		metrics.WriteJSON(w, 400, map[string]string{"error": err.Error()})
		return
	}
	rec := &kgo.Record{Topic: topic, Value: body}
	if k := q.Get("key"); k != "" {
		rec.Key = []byte(k)
	}
	if et := q.Get("event_type"); et != "" {
		rec.Headers = append(rec.Headers, kgo.RecordHeader{Key: events.HeaderEventType, Value: []byte(et)})
	}
	res, err := s.produce(r.Context(), rec, orDefault(q.Get("acks"), s.base.Acks), "sync")
	if err != nil {
		metrics.WriteJSON(w, 503, map[string]any{"error": err.Error()})
		return
	}
	metrics.WriteJSON(w, 201, res)
}

type profileRequest struct {
	Name  string `json:"name"`
	Email string `json:"email"`
	Tier  string `json:"tier"`
}

// putProfile writes the same fact to two topics with different semantics:
//
//	user-events            (delete policy) : full history of changes (event stream)
//	user-profile-compacted (compact policy): latest state per user (changelog / table)
func (s *server) putProfile(w http.ResponseWriter, r *http.Request) {
	userID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		metrics.WriteJSON(w, 400, map[string]string{"error": "bad user id"})
		return
	}
	var req profileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		metrics.WriteJSON(w, 400, map[string]string{"error": err.Error()})
		return
	}
	version, _ := strconv.Atoi(orDefault(r.URL.Query().Get("version"), "0"))
	ev := events.UserProfileEvent{
		EventID: uuid.NewString(), EventType: events.UserProfile, UserID: userID,
		Name: req.Name, Email: req.Email, Tier: req.Tier, Version: version, UpdatedAt: time.Now().UTC(),
	}
	val, _ := json.Marshal(ev)
	key := []byte(fmt.Sprintf("user-%d", userID))
	hdr := []kgo.RecordHeader{{Key: events.HeaderEventType, Value: []byte(ev.EventType)}}
	var out []produceResult
	for _, topic := range []string{"user-events", "user-profile-compacted"} {
		res, err := s.produce(r.Context(), &kgo.Record{Topic: topic, Key: key, Value: val, Headers: hdr}, s.base.Acks, "sync")
		if err != nil {
			metrics.WriteJSON(w, 503, map[string]string{"error": err.Error()})
			return
		}
		out = append(out, res)
	}
	metrics.WriteJSON(w, 200, map[string]any{"event": ev, "results": out})
}

func (s *server) deleteProfile(w http.ResponseWriter, r *http.Request) {
	key := []byte("user-" + r.PathValue("id"))
	// Tombstone: key + null value. After compaction (and delete.retention.ms) the key disappears.
	res, err := s.produce(r.Context(), &kgo.Record{Topic: "user-profile-compacted", Key: key, Value: nil}, s.base.Acks, "sync")
	if err != nil {
		metrics.WriteJSON(w, 503, map[string]string{"error": err.Error()})
		return
	}
	metrics.WriteJSON(w, 200, map[string]any{"tombstone": true, "result": res})
}

func orDefault(v, def string) string {
	if v == "" {
		return def
	}
	return v
}
