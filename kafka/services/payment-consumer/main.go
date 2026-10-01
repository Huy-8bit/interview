// payment-consumer: group `payment-group` on `orders`, produces PaymentSucceeded /
// PaymentFailed on `payments` (key = order_id, so all events of one order stay ordered).
//
// It calls a (simulated) EXTERNAL payment gateway. Kafka cannot make that call
// exactly-once, so the gateway call carries an idempotency key = order_id
// (docs/16-transactions.md "Exactly-once stops at the Kafka boundary").
//
// Error strategy here is different from order-consumer on purpose:
// INLINE_RETRIES blocking retries, then stop-the-line (crash) — payments must
// never be skipped and must keep per-order ordering.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
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

const service = "payment-consumer"

type handler struct {
	log *slog.Logger
	st  *store.Store
	cl  *kgo.Client
}

func main() {
	log := logging.New(service)
	ctx, stop := app.SignalContext()
	defer stop()

	cfg := kafka.ConsumerConfigFromEnv(service)
	cfg.InlineRetries = config.Int("INLINE_RETRIES", 3)
	st := store.New()
	h := &handler{log: log, st: st}
	r, err := kafka.NewRunner(cfg, log, h.handle)
	if err != nil {
		log.Error("cannot create consumer", "err", err)
		os.Exit(1)
	}
	h.cl = r.Client()

	srv := metrics.NewServer(config.String("HTTP_ADDR", ":8080"))
	srv.SetHealth(app.Healthy(r.Healthy, func() error { return st.Ping(context.Background()) }))
	app.RegisterConsumerAdmin(srv, r)
	srv.Start(log)
	_ = r.Run(ctx)
	sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(sctx)
}

func (h *handler) handle(ctx context.Context, rec *kgo.Record) error {
	var ev events.OrderEvent
	if err := json.Unmarshal(rec.Value, &ev); err != nil {
		h.log.Warn("skipping undeserializable order (order-consumer owns the DLQ for it)", "partition", rec.Partition, "offset", rec.Offset)
		return nil
	}
	if ev.EventType != events.OrderCreated {
		return nil
	}

	amount := float64(ev.Quantity) * events.UnitPrice(ev.ProductID)
	pay := events.PaymentEvent{
		SchemaVersion: 1, OrderID: ev.OrderID, UserID: ev.UserID,
		Amount: amount, CausationID: ev.EventID, CreatedAt: time.Now().UTC(),
	}
	switch {
	case ev.Validate() != nil:
		pay.EventType, pay.Reason = events.PaymentFailed, ev.Validate().Error()
	case ev.UserID%17 == 0:
		pay.EventType, pay.Reason = events.PaymentFailed, "card declined (simulated: user_id % 17 == 0)"
	default:
		paymentID, charged, err := h.charge(ctx, ev.OrderID, amount)
		if err != nil {
			return err
		}
		pay.EventType, pay.PaymentID = events.PaymentSucceeded, paymentID
		if !charged {
			metrics.DuplicatesSkipped.WithLabelValues(service, "payment-group").Inc()
			h.log.Warn("gateway idempotency key hit: order already charged, re-emitting same payment",
				"order_id", ev.OrderID, "payment_id", paymentID, "partition", rec.Partition, "offset", rec.Offset)
		}
	}
	// deterministic event id => downstream consumers can dedupe a re-emitted payment
	pay.EventID = uuid.NewSHA1(uuid.NameSpaceOID, []byte(ev.EventID+"/payment")).String()

	val, _ := json.Marshal(pay)
	_, err := kafka.ProduceSync(ctx, h.cl, service, &kgo.Record{
		Topic: "payments", Key: []byte(ev.OrderID), Value: val,
		Headers: []kgo.RecordHeader{
			{Key: events.HeaderEventType, Value: []byte(pay.EventType)},
			{Key: events.HeaderSchemaVersion, Value: []byte("1")},
		},
	})
	return err
}

// charge simulates an external payment API that honours an idempotency key:
// the first call with a key charges, later calls return the original payment.
func (h *handler) charge(ctx context.Context, idemKey string, amount float64) (paymentID string, charged bool, err error) {
	newID := "pay-" + uuid.NewString()[:13]
	ok, err := h.st.R.SetNX(ctx, "lab:gateway:idem:"+idemKey, newID, h.st.TTL).Result()
	if err != nil {
		return "", false, fmt.Errorf("payment gateway unavailable: %w", err)
	}
	if !ok {
		existing, err := h.st.R.Get(ctx, "lab:gateway:idem:"+idemKey).Result()
		return existing, false, err
	}
	pipe := h.st.R.TxPipeline()
	pipe.HIncrBy(ctx, "lab:gateway", "charges", 1)
	pipe.HIncrByFloat(ctx, "lab:gateway", "amount", amount)
	_, err = pipe.Exec(ctx)
	return newID, true, err
}
