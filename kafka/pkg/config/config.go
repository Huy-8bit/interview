// Package config reads service configuration from environment variables.
// Every service in the lab is configured only through env vars (12-factor),
// so docker-compose.yml / .env is the single place to look.
package config

import (
	"os"
	"strconv"
	"strings"
	"time"
)

func String(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

func Int(key string, def int) int {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func Float(key string, def float64) float64 {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if n, err := strconv.ParseFloat(v, 64); err == nil {
			return n
		}
	}
	return def
}

func Bool(key string, def bool) bool {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if b, err := strconv.ParseBool(v); err == nil {
			return b
		}
	}
	return def
}

func Duration(key string, def time.Duration) time.Duration {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return def
}

// List splits a comma separated env var, dropping empty items.
func List(key, def string) []string {
	raw := String(key, def)
	var out []string
	for _, p := range strings.Split(raw, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// Brokers returns the seed brokers. Inside docker: kafka-N:29092 (INTERNAL
// listener). From the host: localhost:9092,localhost:9093,localhost:9094.
func Brokers() []string {
	return List("KAFKA_BROKERS", "localhost:9092,localhost:9093,localhost:9094")
}

// Instance returns a stable instance id for logs/metrics.
func Instance(service string) string {
	if v := String("INSTANCE_ID", ""); v != "" {
		return v
	}
	if h, err := os.Hostname(); err == nil {
		return service + "@" + h
	}
	return service
}
