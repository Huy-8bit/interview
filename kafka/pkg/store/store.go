// Package store wraps Redis for the lab's "side effects" and the idempotent
// consumer pattern (docs/15-idempotence.md).
//
// Why Redis: several consumer instances (and their restarts) must share the
// "already processed" set; an in-memory map would be lost on the very crash we
// want to survive. In production this is usually the same database as the
// business write, updated in ONE transaction with the dedup record.
package store

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/nghuy8bit/kafka-lab/pkg/config"
)

type Store struct {
	R   *redis.Client
	TTL time.Duration
}

func New() *Store {
	return &Store{
		R:   redis.NewClient(&redis.Options{Addr: config.String("REDIS_ADDR", "localhost:6380")}),
		TTL: config.Duration("IDEMPOTENCY_TTL", 24*time.Hour),
	}
}

func (s *Store) Ping(ctx context.Context) error { return s.R.Ping(ctx).Err() }

// applyOnce atomically: if dedupKey does not exist -> create it and HINCRBY each
// (hash, field, delta); return 1. Otherwise do nothing and return 0.
// Atomicity matters: "mark processed" and "apply effect" must not be separable
// by a crash, otherwise we get either loss (mark w/o effect) or dup (effect w/o mark).
var applyOnce = redis.NewScript(`
if redis.call('SET', KEYS[1], ARGV[1], 'NX', 'PX', ARGV[2]) then
  local i = 3
  while i <= #ARGV do
    redis.call('HINCRBY', ARGV[i], ARGV[i+1], tonumber(ARGV[i+2]))
    i = i + 3
  end
  return 1
end
return 0
`)

// Effect is one counter increment applied as part of an idempotent operation.
type Effect struct {
	Hash  string
	Field string
	Delta int64
}

// ApplyOnce applies effects only if dedupKey was never seen. Returns applied=false for duplicates.
func (s *Store) ApplyOnce(ctx context.Context, dedupKey, owner string, effects ...Effect) (bool, error) {
	args := []any{owner, s.TTL.Milliseconds()}
	for _, e := range effects {
		args = append(args, e.Hash, e.Field, e.Delta)
	}
	n, err := applyOnce.Run(ctx, s.R, []string{dedupKey}, args...).Int()
	if err != nil {
		return false, fmt.Errorf("redis apply-once: %w", err)
	}
	return n == 1, nil
}

// Incr applies a NON idempotent effect (counts every delivery, duplicates included).
func (s *Store) Incr(ctx context.Context, hash, field string, delta int64) error {
	pipe := s.R.TxPipeline()
	pipe.HIncrBy(ctx, hash, field, delta)
	pipe.Expire(ctx, hash, s.TTL)
	_, err := pipe.Exec(ctx)
	return err
}

// Once returns true the first time it is called for key (used for one-shot lab faults).
func (s *Store) Once(ctx context.Context, key string) (bool, error) {
	return s.R.SetNX(ctx, key, "1", s.TTL).Result()
}

func (s *Store) IsMember(ctx context.Context, set, member string) (bool, error) {
	return s.R.SIsMember(ctx, set, member).Result()
}

// AppendSeq records the order in which a consumer saw sequence numbers (ordering lab).
func (s *Store) AppendSeq(ctx context.Context, list string, v any) error {
	pipe := s.R.TxPipeline()
	pipe.RPush(ctx, list, v)
	pipe.Expire(ctx, list, s.TTL)
	_, err := pipe.Exec(ctx)
	return err
}
