// order-consumer: consumer group `order-processing-group` on topic `orders`.
//
// For every OrderCreated it "reserves inventory":
//   - a NON idempotent counter   lab:order:<id> deliveries      (+1 on every delivery, duplicates included)
//   - an IDEMPOTENT effect       lab:order:<id> reserved_qty    (applied once per event_id, Lua/Redis)
//   - emits InventoryReserved on `inventory-events` (key = product_id)
//
// Comparing the two counters after a crash shows the difference between
// "Kafka delivered twice" and "the business effect happened twice" (labs/08).
//
// Failures go orders -> retry-orders (attempt 1..MAX_RETRIES, exponential
// backoff) -> orders-dlq. The retry topic is consumed by a second runner in the
// same process with group `order-processing-group-retry`.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
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
	"github.com/nghuy8bit/kafka-lab/pkg/store"
)

const service = "order-consumer"

// Redis set of product ids whose "inventory service" is down. Labs add/remove
// members to simulate a transient dependency failure (then replay the DLQ).
const failingProducts = "lab:failing-products"

type handler struct {
	log      *slog.Logger
	st       *store.Store
	group    string
	instance string
	cl       *kgo.Client // set after the runner is created (used to emit inventory-events)
}

func main() {
	log := logging.New(service)
	ctx, stop := app.SignalContext()
	defer stop()

	cfg := kafka.ConsumerConfigFromEnv(service)
	st := store.New()
	h := &handler{log: log, st: st, group: cfg.Group, instance: cfg.Instance}

	mainRunner, err := kafka.NewRunner(cfg, log, h.handle)
	if err != nil {
		log.Error("cannot create consumer", "err", err)
		os.Exit(1)
	}
	h.cl = mainRunner.Client()
	runners := []*kafka.Runner{mainRunner}
	if cfg.RetryTopic != "" {
		retryRunner, err := kafka.NewRunner(cfg.RetryStageConfig(), log, h.handle)
		if err != nil {
			log.Error("cannot create retry consumer", "err", err)
			os.Exit(1)
		}
		runners = append(runners, retryRunner)
	}

	srv := metrics.NewServer(config.String("HTTP_ADDR", ":8080"))
	checks := []func() error{func() error { return st.Ping(context.Background()) }}
	for _, r := range runners {
		checks = append(checks, r.Healthy)
	}
	srv.SetHealth(app.Healthy(checks...))
	app.RegisterConsumerAdmin(srv, runners...)
	srv.Start(log)

	var wg sync.WaitGroup
	for _, r := range runners {
		wg.Add(1)
		go func() { defer wg.Done(); _ = r.Run(ctx) }()
	}
	wg.Wait()
	sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(sctx)
}

func (h *handler) handle(ctx context.Context, rec *kgo.Record) error {
	var ev events.OrderEvent
	if err := json.Unmarshal(rec.Value, &ev); err != nil {
		// cannot ever succeed -> straight to DLQ, no retries
		return kafka.Permanent(fmt.Errorf("cannot deserialize order event: %w", err))
	}
	if ev.EventType == "" || ev.EventID == "" {
		return kafka.Permanent(errors.New("missing event_type/event_id"))
	}

	if ev.LabFault == events.FaultCrashBeforeProcess {
		if first, _ := h.st.Once(ctx, "lab:crashed:before:"+ev.EventID); first {
			h.log.Error("LAB FAULT: simulated crash BEFORE processing", "topic", rec.Topic,
				"partition", rec.Partition, "offset", rec.Offset, "key", string(rec.Key), "event_id", ev.EventID)
			os.Exit(1)
		}
	}
	if ev.LabFault == events.FaultSlow {
		time.Sleep(5 * time.Second)
	}

	switch ev.EventType {
	case events.OrderCreated:
		if err := h.orderCreated(ctx, rec, ev); err != nil {
			return err
		}
	case events.OrderUpdated:
		h.orderUpdated(ctx, rec, ev)
	default:
		h.log.Debug("ignoring event type", "event_type", ev.EventType)
	}

	if ev.LabFault == events.FaultCrashAfterProcess {
		if first, _ := h.st.Once(ctx, "lab:crashed:after:"+ev.EventID); first {
			h.log.Error("LAB FAULT: simulated crash AFTER processing, BEFORE offset commit", "topic", rec.Topic,
				"partition", rec.Partition, "offset", rec.Offset, "key", string(rec.Key), "event_id", ev.EventID)
			os.Exit(1)
		}
	}
	return nil
}

func (h *handler) orderCreated(ctx context.Context, rec *kgo.Record, ev events.OrderEvent) error {
	if err := ev.Validate(); err != nil {
		return err // retryable on purpose (see events.Validate doc): shows retry x3 -> DLQ
	}
	if down, err := h.st.IsMember(ctx, failingProducts, strconv.FormatInt(ev.ProductID, 10)); err != nil {
		return fmt.Errorf("redis: %w", err)
	} else if down {
		return fmt.Errorf("inventory service unavailable for product %d", ev.ProductID)
	}

	orderKey := "lab:order:" + ev.OrderID
	// 1) NOT idempotent: counts deliveries
	if err := h.st.Incr(ctx, orderKey, "deliveries", 1); err != nil {
		return err
	}
	// 2) idempotent: dedup on event_id, effect + "processed" marker in one atomic step
	applied, err := h.st.ApplyOnce(ctx, "processed:"+h.group+":"+ev.EventID, h.instance,
		store.Effect{Hash: orderKey, Field: "reserved_qty", Delta: int64(ev.Quantity)},
		store.Effect{Hash: "lab:inventory:reserved", Field: strconv.FormatInt(ev.ProductID, 10), Delta: int64(ev.Quantity)},
		store.Effect{Hash: "lab:stats", Field: "orders_reserved", Delta: 1},
	)
	if err != nil {
		return err
	}
	if !applied {
		metrics.DuplicatesSkipped.WithLabelValues(service, h.group).Inc()
		h.log.Warn("DUPLICATE delivery detected: event already processed, side effect skipped",
			"topic", rec.Topic, "partition", rec.Partition, "offset", rec.Offset, "key", string(rec.Key), "event_id", ev.EventID)
		return nil
	}

	inv := events.InventoryEvent{
		// deterministic id: a redelivery of the same order produces the same event id
		EventID:   uuid.NewSHA1(uuid.NameSpaceOID, []byte(ev.EventID+"/inventory")).String(),
		EventType: events.InventoryReserve, ProductID: ev.ProductID, OrderID: ev.OrderID,
		Quantity: ev.Quantity, CausationID: ev.EventID, CreatedAt: time.Now().UTC(),
	}
	val, _ := json.Marshal(inv)
	_, err = kafka.ProduceSync(ctx, h.cl, service, &kgo.Record{
		Topic: "inventory-events", Key: []byte(strconv.FormatInt(ev.ProductID, 10)), Value: val,
		Headers: []kgo.RecordHeader{{Key: events.HeaderEventType, Value: []byte(inv.EventType)}},
	})
	return err
}

// orderUpdated records the sequence numbers in arrival order so the ordering
// lab can verify them (Redis list lab:seq:<order_id>).
func (h *handler) orderUpdated(ctx context.Context, rec *kgo.Record, ev events.OrderEvent) {
	entry := fmt.Sprintf("seq=%d partition=%d offset=%d consumer=%s", ev.Sequence, rec.Partition, rec.Offset, h.instance)
	_ = h.st.AppendSeq(ctx, "lab:seq:"+ev.OrderID, entry)
	last, _ := h.st.R.HGet(ctx, "lab:order:"+ev.OrderID, "last_seq").Int()
	if ev.Sequence < last {
		h.log.Warn("OUT OF ORDER sequence", "order_id", ev.OrderID, "sequence", ev.Sequence, "last_seen", last)
	}
	_ = h.st.R.HSet(ctx, "lab:order:"+ev.OrderID, "last_seq", ev.Sequence).Err()
}
