// analytics-consumer: group `analytics-group` on `orders` + `payments`.
//
// Demonstrates BATCH processing + AUTO commit:
//   - every polled batch (up to MAX_POLL_RECORDS) is aggregated in memory per product
//   - AfterBatch flushes one OrderStatsWindow event per product to `analytics-events`
//     (12 partitions, key = product_id)
//   - offsets are committed by the client's auto-commit timer (COMMIT_MODE=auto):
//     analytics can tolerate a few duplicates after a crash, so it trades exactness
//     for simplicity. Compare with order-consumer (manual commit).
package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/app"
	"github.com/nghuy8bit/kafka-lab/pkg/config"
	"github.com/nghuy8bit/kafka-lab/pkg/events"
	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
	"github.com/nghuy8bit/kafka-lab/pkg/logging"
	"github.com/nghuy8bit/kafka-lab/pkg/metrics"
)

const service = "analytics-consumer"

var (
	ordersTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "analytics_orders_total", Help: "OrderCreated events aggregated."})
	revenueTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "analytics_revenue_total", Help: "Sum of PaymentSucceeded amounts."})
	batchSize = prometheus.NewHistogram(prometheus.HistogramOpts{
		Name: "analytics_batch_records", Help: "Records per processed poll batch.",
		Buckets: []float64{1, 5, 10, 25, 50, 100, 250, 500, 1000}})
)

type agg struct {
	orders, units int
	revenue       float64
}

type handler struct {
	log         *slog.Logger
	cl          *kgo.Client
	mu          sync.Mutex
	window      map[int64]*agg
	windowStart time.Time
	batchCount  int
}

func main() {
	log := logging.New(service)
	metrics.Registry.MustRegister(ordersTotal, revenueTotal, batchSize)
	ctx, stop := app.SignalContext()
	defer stop()

	cfg := kafka.ConsumerConfigFromEnv(service)
	h := &handler{log: log, window: map[int64]*agg{}, windowStart: time.Now()}
	r, err := kafka.NewRunner(cfg, log, h.handle)
	if err != nil {
		log.Error("cannot create consumer", "err", err)
		os.Exit(1)
	}
	h.cl = r.Client()
	r.AfterBatch = h.flush

	srv := metrics.NewServer(config.String("HTTP_ADDR", ":8080"))
	srv.SetHealth(r.Healthy)
	app.RegisterConsumerAdmin(srv, r)
	srv.Start(log)
	_ = r.Run(ctx)
	sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(sctx)
}

func (h *handler) handle(_ context.Context, rec *kgo.Record) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.batchCount++
	switch rec.Topic {
	case "orders":
		var ev events.OrderEvent
		if json.Unmarshal(rec.Value, &ev) != nil || ev.EventType != events.OrderCreated || ev.Validate() != nil {
			return nil
		}
		a := h.window[ev.ProductID]
		if a == nil {
			a = &agg{}
			h.window[ev.ProductID] = a
		}
		a.orders++
		a.units += ev.Quantity
		ordersTotal.Inc()
	case "payments":
		var ev events.PaymentEvent
		if json.Unmarshal(rec.Value, &ev) == nil && ev.EventType == events.PaymentSucceeded {
			revenueTotal.Add(ev.Amount)
		}
	}
	return nil
}

// flush runs once per poll batch: one aggregated event per product.
func (h *handler) flush(ctx context.Context) error {
	h.mu.Lock()
	window, start, n := h.window, h.windowStart, h.batchCount
	h.window, h.windowStart, h.batchCount = map[int64]*agg{}, time.Now(), 0
	h.mu.Unlock()
	batchSize.Observe(float64(n))
	if len(window) == 0 {
		return nil
	}
	end := time.Now().UTC()
	for pid, a := range window {
		ev := events.AnalyticsEvent{
			EventID: uuid.NewString(), EventType: events.OrderStats, ProductID: pid,
			Orders: a.orders, Units: a.units, Revenue: float64(a.units) * events.UnitPrice(pid),
			WindowStart: start.UTC(), WindowEnd: end,
		}
		val, _ := json.Marshal(ev)
		kafka.ProduceAsync(ctx, h.cl, service, &kgo.Record{
			Topic: "analytics-events", Key: []byte(strconv.FormatInt(pid, 10)), Value: val,
			Headers: []kgo.RecordHeader{{Key: events.HeaderEventType, Value: []byte(ev.EventType)}},
		}, nil)
	}
	h.log.Debug("batch flushed", "records", n, "products", len(window))
	return h.cl.Flush(ctx)
}
