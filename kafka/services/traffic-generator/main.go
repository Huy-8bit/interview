// traffic-generator: produces a steady / bursty / skewed stream of OrderCreated
// events directly into Kafka (franz-go async producer).
//
// Env (defaults in docker-compose.yml):
//
//	MODE=constant|burst|skewed-key   RATE_PER_SECOND=1000   DURATION=60s (0 = forever)
//	BURST_RATE=10000  BURST_DURATION=10s  BURST_INTERVAL=30s
//	HOT_KEY_RATIO=0.8 HOT_KEY=order-HOT   PAYLOAD_BYTES=0     TOPIC=orders
//
// HTTP control (so labs can change traffic without restarting containers):
//
//	POST /start?mode=burst&rate=1000&duration=60s&burst_rate=10000&burst_duration=10s&hot_ratio=0.8
//	POST /stop
//	GET  /status
package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/app"
	"github.com/nghuy8bit/kafka-lab/pkg/config"
	"github.com/nghuy8bit/kafka-lab/pkg/events"
	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
	"github.com/nghuy8bit/kafka-lab/pkg/logging"
	"github.com/nghuy8bit/kafka-lab/pkg/metrics"
)

const service = "traffic-generator"

type Plan struct {
	Mode          string        `json:"mode"`
	Rate          float64       `json:"rate_per_second"`
	Duration      time.Duration `json:"duration"`
	BurstRate     float64       `json:"burst_rate"`
	BurstDuration time.Duration `json:"burst_duration"`
	BurstInterval time.Duration `json:"burst_interval"`
	HotKeyRatio   float64       `json:"hot_key_ratio"`
	HotKey        string        `json:"hot_key"`
	PayloadBytes  int           `json:"payload_bytes"`
	Topic         string        `json:"topic"`
}

type gen struct {
	log *slog.Logger
	cl  *kgo.Client

	mu      sync.Mutex
	cancel  context.CancelFunc
	done    chan struct{}
	plan    Plan
	started time.Time

	sent, failed, hot atomic.Int64
}

func planFromEnv() Plan {
	return Plan{
		Mode:          config.String("MODE", "constant"),
		Rate:          config.Float("RATE_PER_SECOND", 5),
		Duration:      config.Duration("DURATION", 0),
		BurstRate:     config.Float("BURST_RATE", 10000),
		BurstDuration: config.Duration("BURST_DURATION", 10*time.Second),
		BurstInterval: config.Duration("BURST_INTERVAL", 30*time.Second),
		HotKeyRatio:   config.Float("HOT_KEY_RATIO", 0.8),
		HotKey:        config.String("HOT_KEY", "order-HOT"),
		PayloadBytes:  config.Int("PAYLOAD_BYTES", 0),
		Topic:         config.String("TOPIC", "orders"),
	}
}

func main() {
	log := logging.New(service)
	ctx, stop := app.SignalContext()
	defer stop()

	pc := kafka.ProducerConfigFromEnv()
	cl, err := kafka.NewProducer(service, pc, log, kgo.MaxBufferedRecords(50_000))
	if err != nil {
		log.Error("cannot create producer", "err", err)
		os.Exit(1)
	}
	g := &gen{log: log, cl: cl}
	log.Info("traffic generator ready", "producer", pc.String())

	srv := metrics.NewServer(config.String("HTTP_ADDR", ":8080"))
	srv.SetHealth(func() error {
		hctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		return cl.Ping(hctx)
	})
	srv.Handle("POST /start", g.handleStart)
	srv.Handle("POST /stop", func(w http.ResponseWriter, r *http.Request) {
		g.stop()
		metrics.WriteJSON(w, 200, g.status())
	})
	srv.Handle("GET /status", func(w http.ResponseWriter, r *http.Request) { metrics.WriteJSON(w, 200, g.status()) })
	srv.Start(log)

	if config.Bool("AUTOSTART", true) {
		g.start(planFromEnv())
	}
	<-ctx.Done()
	g.stop()
	sctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	_ = cl.Flush(sctx)
	cl.Close()
	_ = srv.Shutdown(sctx)
	log.Info("shutdown complete", "sent", g.sent.Load(), "failed", g.failed.Load())
}

func (g *gen) handleStart(w http.ResponseWriter, r *http.Request) {
	p := planFromEnv()
	q := r.URL.Query()
	set := func(k string, fn func(string)) {
		if v := q.Get(k); v != "" {
			fn(v)
		}
	}
	set("mode", func(v string) { p.Mode = v })
	set("rate", func(v string) { p.Rate, _ = strconv.ParseFloat(v, 64) })
	set("duration", func(v string) { p.Duration, _ = time.ParseDuration(v) })
	set("burst_rate", func(v string) { p.BurstRate, _ = strconv.ParseFloat(v, 64) })
	set("burst_duration", func(v string) { p.BurstDuration, _ = time.ParseDuration(v) })
	set("burst_interval", func(v string) { p.BurstInterval, _ = time.ParseDuration(v) })
	set("hot_ratio", func(v string) { p.HotKeyRatio, _ = strconv.ParseFloat(v, 64) })
	set("hot_key", func(v string) { p.HotKey = v })
	set("payload_bytes", func(v string) { p.PayloadBytes, _ = strconv.Atoi(v) })
	set("topic", func(v string) { p.Topic = v })
	switch p.Mode {
	case "constant", "burst", "skewed-key":
	default:
		metrics.WriteJSON(w, 400, map[string]string{"error": "mode must be constant|burst|skewed-key"})
		return
	}
	g.stop()
	g.start(p)
	metrics.WriteJSON(w, 200, g.status())
}

func (g *gen) start(p Plan) {
	ctx, cancel := context.WithCancel(context.Background())
	if p.Duration > 0 {
		ctx, cancel = context.WithTimeout(context.Background(), p.Duration)
	}
	g.mu.Lock()
	g.cancel, g.done, g.plan, g.started = cancel, make(chan struct{}), p, time.Now()
	g.sent.Store(0)
	g.failed.Store(0)
	g.hot.Store(0)
	done := g.done
	g.mu.Unlock()
	g.log.Info("traffic started", "mode", p.Mode, "rate", p.Rate, "duration", p.Duration,
		"burst_rate", p.BurstRate, "hot_ratio", p.HotKeyRatio, "topic", p.Topic)
	go func() {
		defer close(done)
		g.loop(ctx, p)
		_ = g.cl.Flush(context.Background())
		g.log.Info("traffic finished", "sent", g.sent.Load(), "failed", g.failed.Load(), "hot_key_records", g.hot.Load())
	}()
}

func (g *gen) stop() {
	g.mu.Lock()
	cancel, done := g.cancel, g.done
	g.cancel = nil
	g.mu.Unlock()
	if cancel != nil {
		cancel()
		<-done
	}
}

func (g *gen) status() map[string]any {
	g.mu.Lock()
	defer g.mu.Unlock()
	running := g.cancel != nil
	if running {
		select {
		case <-g.done:
			running = false
		default:
		}
	}
	elapsed := time.Since(g.started).Seconds()
	return map[string]any{
		"running": running, "plan": g.plan, "started_at": g.started,
		"sent": g.sent.Load(), "failed": g.failed.Load(), "hot_key_records": g.hot.Load(),
		"avg_rate": float64(g.sent.Load()) / max(elapsed, 0.001),
	}
}

// currentRate implements the burst schedule: BURST_RATE during the first
// BURST_DURATION of every BURST_INTERVAL, base rate otherwise.
func currentRate(p Plan, elapsed time.Duration) float64 {
	if p.Mode != "burst" {
		return p.Rate
	}
	if p.BurstInterval <= 0 || elapsed%p.BurstInterval < p.BurstDuration {
		return p.BurstRate
	}
	return p.Rate
}

func (g *gen) loop(ctx context.Context, p Plan) {
	const tick = 10 * time.Millisecond
	t := time.NewTicker(tick)
	defer t.Stop()
	start := time.Now()
	var carry float64
	padding := strings.Repeat("x", p.PayloadBytes)
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		carry += currentRate(p, time.Since(start)) * tick.Seconds()
		n := int(carry)
		carry -= float64(n)
		for i := 0; i < n; i++ {
			ev := events.NewOrderCreated(int64(1000+rand.IntN(9000)), int64(1+rand.IntN(1000)), 1+rand.IntN(5))
			ev.Padding = padding
			key := ev.OrderID
			if p.Mode == "skewed-key" && rand.Float64() < p.HotKeyRatio {
				key = p.HotKey
				ev.OrderID = p.HotKey
				g.hot.Add(1)
			}
			val, _ := json.Marshal(ev)
			rec := &kgo.Record{Topic: p.Topic, Key: []byte(key), Value: val, Headers: []kgo.RecordHeader{
				{Key: events.HeaderEventType, Value: []byte(ev.EventType)},
				{Key: events.HeaderProducer, Value: []byte(service)},
			}}
			// Produce blocks when MaxBufferedRecords is reached: producer side backpressure.
			kafka.ProduceAsync(context.Background(), g.cl, service, rec, func(_ *kgo.Record, err error) {
				if err != nil {
					g.failed.Add(1)
					return
				}
				g.sent.Add(1)
			})
		}
	}
}
