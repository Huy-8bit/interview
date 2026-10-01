// Package logging configures slog with a logfmt style text handler, e.g.
//
//	level=INFO msg=consumed consumer=order-consumer-2 group=order-processing-group topic=orders partition=3 offset=10232 key=order-921
//
// logfmt is easy to grep in `docker compose logs` which is how most labs are observed.
package logging

import (
	"log/slog"
	"os"
	"strings"
	"time"

	"github.com/nghuy8bit/kafka-lab/pkg/config"
)

func New(service string) *slog.Logger {
	level := slog.LevelInfo
	switch strings.ToLower(config.String("LOG_LEVEL", "info")) {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	}
	h := slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: level,
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			if a.Key == slog.TimeKey && len(groups) == 0 {
				return slog.String(slog.TimeKey, a.Value.Time().Format("15:04:05.000"))
			}
			if a.Value.Kind() == slog.KindDuration {
				return slog.String(a.Key, a.Value.Duration().Round(time.Microsecond).String())
			}
			return a
		},
	})
	l := slog.New(h).With("service", service)
	slog.SetDefault(l)
	return l
}
