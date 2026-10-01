// Package metrics holds the Prometheus metrics shared by every Go service and
// a tiny HTTP server exposing /metrics, /health and service specific /admin routes.
//
// Metric names follow the lab spec (docs/20-monitoring.md):
//
//	produced_total, produce_error_total, produce_latency_seconds
//	consumed_total, consume_error_total, processing_duration_seconds
//	retry_total, dlq_total, duplicate_skipped_total, rebalance_events_total ...
//
// The Prometheus job/instance labels identify which container emitted them.
package metrics

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var Registry = prometheus.NewRegistry()

var latencyBuckets = []float64{.0005, .001, .0025, .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10, 30}

var (
	Produced = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "produced_total", Help: "Records acknowledged by the broker.",
	}, []string{"service", "topic"})
	ProduceErrors = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "produce_error_total", Help: "Records that failed to produce (after client retries).",
	}, []string{"service", "topic", "error"})
	ProduceLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name: "produce_latency_seconds", Help: "Time from Produce() to broker ack (includes linger + batching + replication for acks=all).",
		Buckets: latencyBuckets,
	}, []string{"service", "topic"})

	Consumed = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "consumed_total", Help: "Records handed to the business handler.",
	}, []string{"service", "group", "topic", "partition"})
	ConsumeErrors = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "consume_error_total", Help: "Handler failures (each failure is then retried or dead-lettered).",
	}, []string{"service", "group", "topic"})
	ProcessingDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name: "processing_duration_seconds", Help: "Business handler duration per record.",
		Buckets: latencyBuckets,
	}, []string{"service", "group", "topic"})
	EndToEndLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name: "end_to_end_latency_seconds", Help: "now - record timestamp when processing finished (grows with consumer lag).",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10, 30, 60, 120, 300},
	}, []string{"service", "group", "topic"})
	Retries = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "retry_total", Help: "Records sent to the retry topic.",
	}, []string{"service", "group", "topic"})
	DLQ = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "dlq_total", Help: "Records sent to the dead letter topic.",
	}, []string{"service", "group", "topic"})
	DuplicatesSkipped = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "duplicate_skipped_total", Help: "Records detected as already processed (idempotent consumer).",
	}, []string{"service", "group"})
	Commits = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "offset_commit_total", Help: "Offset commits issued by the consumer runner.",
	}, []string{"service", "group", "result"})
	Rebalances = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "rebalance_events_total", Help: "Partition assignment callbacks (assigned / revoked / lost).",
	}, []string{"service", "group", "event"})
	AssignedPartitions = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "assigned_partitions", Help: "Partitions currently owned by this consumer instance.",
	}, []string{"service", "group", "topic"})
)

func init() {
	Registry.MustRegister(
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
		Produced, ProduceErrors, ProduceLatency,
		Consumed, ConsumeErrors, ProcessingDuration, EndToEndLatency,
		Retries, DLQ, DuplicatesSkipped, Commits, Rebalances, AssignedPartitions,
	)
}

// Server is the per-service HTTP server: /metrics, /health and extra routes.
type Server struct {
	mux    *http.ServeMux
	srv    *http.Server
	mu     sync.RWMutex
	health func() error
}

func NewServer(addr string) *Server {
	s := &Server{mux: http.NewServeMux()}
	s.srv = &http.Server{Addr: addr, Handler: s.mux, ReadHeaderTimeout: 5 * time.Second}
	s.mux.Handle("/metrics", promhttp.HandlerFor(Registry, promhttp.HandlerOpts{Registry: Registry}))
	s.mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		s.mu.RLock()
		h := s.health
		s.mu.RUnlock()
		if h != nil {
			if err := h(); err != nil {
				WriteJSON(w, http.StatusServiceUnavailable, map[string]any{"status": "unhealthy", "error": err.Error()})
				return
			}
		}
		WriteJSON(w, http.StatusOK, map[string]any{"status": "ok"})
	})
	return s
}

// SetHealth registers the readiness/liveness check used by /health (and the
// docker compose healthcheck).
func (s *Server) SetHealth(fn func() error) {
	s.mu.Lock()
	s.health = fn
	s.mu.Unlock()
}

func (s *Server) Handle(pattern string, h http.HandlerFunc) { s.mux.HandleFunc(pattern, h) }

func (s *Server) Start(log *slog.Logger) {
	go func() {
		log.Info("http server listening", "addr", s.srv.Addr)
		if err := s.srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("http server failed", "err", err)
		}
	}()
}

func (s *Server) Shutdown(ctx context.Context) error { return s.srv.Shutdown(ctx) }

func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}
