// Package app holds the boilerplate shared by the service mains: signal
// handling (graceful shutdown on SIGTERM/SIGINT) and the consumer admin routes.
package app

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
	"github.com/nghuy8bit/kafka-lab/pkg/metrics"
)

// SignalContext is cancelled on SIGINT/SIGTERM. `docker stop` sends SIGTERM,
// waits stop_grace_period (30s in compose) and only then SIGKILLs.
func SignalContext() (context.Context, context.CancelFunc) {
	return signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
}

// RegisterConsumerAdmin exposes:
//
//	GET  /admin/state           assignment, commit mode, delay ... of every runner
//	POST /admin/delay?ms=200    change the simulated processing time at runtime (backpressure lab)
//	POST /admin/log-every?n=100 log only 1 of N processed records
func RegisterConsumerAdmin(srv *metrics.Server, runners ...*kafka.Runner) {
	srv.Handle("/admin/state", func(w http.ResponseWriter, r *http.Request) {
		out := make([]map[string]any, 0, len(runners))
		for _, rn := range runners {
			out = append(out, rn.State())
		}
		metrics.WriteJSON(w, http.StatusOK, out)
	})
	RegisterLogEvery(srv, runners...)
	srv.Handle("/admin/delay", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			metrics.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST /admin/delay?ms=N"})
			return
		}
		ms, err := strconv.Atoi(r.URL.Query().Get("ms"))
		if err != nil || ms < 0 {
			metrics.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "ms must be a non-negative integer"})
			return
		}
		// only the main-topic runner is slowed down, never the retry stage
		runners[0].SetDelay(time.Duration(ms) * time.Millisecond)
		runners[0].Logger().Info("processing delay changed", "delay_ms", ms)
		metrics.WriteJSON(w, http.StatusOK, map[string]any{"delay_ms": ms})
	})
}

// RegisterLogEvery: POST /admin/log-every?n=1000 logs 1 of N processed records
// (keeps `docker compose logs` usable during high-throughput labs).
func RegisterLogEvery(srv *metrics.Server, runners ...*kafka.Runner) {
	srv.Handle("/admin/log-every", func(w http.ResponseWriter, r *http.Request) {
		n, err := strconv.Atoi(r.URL.Query().Get("n"))
		if r.Method != http.MethodPost || err != nil || n < 1 {
			metrics.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "POST /admin/log-every?n=N (N>=1)"})
			return
		}
		for _, rn := range runners {
			rn.SetLogEvery(n)
		}
		metrics.WriteJSON(w, http.StatusOK, map[string]any{"log_every": n})
	})
}

// Healthy returns an aggregated health func for /health.
func Healthy(checks ...func() error) func() error {
	return func() error {
		for _, c := range checks {
			if err := c(); err != nil {
				return err
			}
		}
		return nil
	}
}
