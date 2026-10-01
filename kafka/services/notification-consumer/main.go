// notification-consumer: group `notification-group` on `orders` AND `payments`.
//
//	OrderCreated                  -> "order received" e-mail
//	PaymentSucceeded/PaymentFailed -> "payment result" e-mail
//
// Each notification is emitted on `notifications` (key = user id) at most once
// per source event_id (idempotent consumer, Redis dedup), so a redelivered
// payment does not send a second e-mail.
// Failures: retry-payments (x MAX_RETRIES) -> payments-dlq.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
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

const service = "notification-consumer"

type handler struct {
	log   *slog.Logger
	st    *store.Store
	group string
	cl    *kgo.Client
}

func main() {
	log := logging.New(service)
	ctx, stop := app.SignalContext()
	defer stop()

	cfg := kafka.ConsumerConfigFromEnv(service)
	st := store.New()
	h := &handler{log: log, st: st, group: cfg.Group}
	mainRunner, err := kafka.NewRunner(cfg, log, h.handle)
	if err != nil {
		log.Error("cannot create consumer", "err", err)
		os.Exit(1)
	}
	h.cl = mainRunner.Client()
	runners := []*kafka.Runner{mainRunner}
	if cfg.RetryTopic != "" {
		rr, err := kafka.NewRunner(cfg.RetryStageConfig(), log, h.handle)
		if err != nil {
			log.Error("cannot create retry consumer", "err", err)
			os.Exit(1)
		}
		runners = append(runners, rr)
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
	var (
		n      events.NotificationEvent
		source string
	)
	switch rec.Topic {
	case "orders":
		var ev events.OrderEvent
		if err := json.Unmarshal(rec.Value, &ev); err != nil || ev.EventType != events.OrderCreated {
			return nil // order-consumer is the owner of orders-dlq
		}
		source = ev.EventID
		n = events.NotificationEvent{Channel: "email", UserID: ev.UserID, OrderID: ev.OrderID, Template: "order-received"}
	default: // payments (or retry-payments carrying a payment)
		var ev events.PaymentEvent
		if err := json.Unmarshal(rec.Value, &ev); err != nil {
			return kafka.Permanent(fmt.Errorf("cannot deserialize payment event: %w", err))
		}
		if ev.EventID == "" || ev.OrderID == "" {
			return kafka.Permanent(fmt.Errorf("payment event missing event_id/order_id"))
		}
		if ev.Amount <= 0 {
			return fmt.Errorf("invalid payment amount %.2f for order %s", ev.Amount, ev.OrderID)
		}
		source = ev.EventID
		tpl := "payment-succeeded"
		if ev.EventType == events.PaymentFailed {
			tpl = "payment-failed"
		}
		n = events.NotificationEvent{Channel: "email", UserID: ev.UserID, OrderID: ev.OrderID, Template: tpl}
	}

	applied, err := h.st.ApplyOnce(ctx, "processed:"+h.group+":"+source, service,
		store.Effect{Hash: "lab:notifications", Field: n.Template, Delta: 1})
	if err != nil {
		return err
	}
	if !applied {
		metrics.DuplicatesSkipped.WithLabelValues(service, h.group).Inc()
		h.log.Warn("DUPLICATE source event, e-mail not sent twice", "topic", rec.Topic, "partition", rec.Partition, "offset", rec.Offset)
		return nil
	}
	n.EventID = uuid.NewSHA1(uuid.NameSpaceOID, []byte(source+"/notification")).String()
	n.EventType, n.CausationID, n.CreatedAt = events.NotificationSent, source, time.Now().UTC()
	val, _ := json.Marshal(n)
	_, err = kafka.ProduceSync(ctx, h.cl, service, &kgo.Record{
		Topic: "notifications", Key: []byte(fmt.Sprintf("user-%d", n.UserID)), Value: val,
		Headers: []kgo.RecordHeader{{Key: events.HeaderEventType, Value: []byte(n.EventType)}},
	})
	return err
}
