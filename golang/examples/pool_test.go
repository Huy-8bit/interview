package labs

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"
)

func waitError(t *testing.T, done <-chan error) error {
	t.Helper()
	select {
	case err := <-done:
		return err
	case <-time.After(3 * time.Second):
		t.Fatal("workers did not join")
		return nil
	}
}
func TestPoolCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	jobs := make(chan int, 3)
	jobs <- 1
	jobs <- 2
	jobs <- 3
	close(jobs)
	started := make(chan struct{}, 2)
	var active atomic.Int64
	done := make(chan error, 1)
	go func() {
		done <- RunPool(ctx, 2, jobs, func(ctx context.Context, n int) error {
			active.Add(1)
			defer active.Add(-1)
			started <- struct{}{}
			<-ctx.Done()
			return ctx.Err()
		})
	}()
	for i := 0; i < 2; i++ {
		select {
		case <-started:
		case <-time.After(3 * time.Second):
			t.Fatal("worker failed to start")
		}
	}
	cancel()
	if err := waitError(t, done); !errors.Is(err, context.Canceled) {
		t.Fatalf("got %v", err)
	}
	if active.Load() != 0 {
		t.Fatal("return before workers joined")
	}
}
func TestPoolComplete(t *testing.T) {
	jobs := make(chan int, 100)
	for i := 0; i < 100; i++ {
		jobs <- i
	}
	close(jobs)
	var sum atomic.Int64
	if err := RunPool(context.Background(), 4, jobs, func(ctx context.Context, n int) error { sum.Add(int64(n)); return nil }); err != nil {
		t.Fatal(err)
	}
	if sum.Load() != 4950 {
		t.Fatalf("lost or duplicate work: %d", sum.Load())
	}
}
func TestPoolErrorCancelsSiblings(t *testing.T) {
	jobs := make(chan int, 1)
	jobs <- 1
	want := errors.New("task failed")
	done := make(chan error, 1)
	go func() {
		done <- RunPool(context.Background(), 2, jobs, func(context.Context, int) error { return want })
	}()
	if err := waitError(t, done); !errors.Is(err, want) {
		t.Fatalf("got %v", err)
	}
	close(jobs)
}
func TestPoolRejectsInvalidWorkers(t *testing.T) {
	if err := RunPool(context.Background(), 0, nil, func(context.Context, int) error { return nil }); err == nil {
		t.Fatal("expected validation error")
	}
}
