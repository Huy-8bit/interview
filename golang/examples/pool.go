package labs

import (
	"context"
	"errors"
	"sync"
)

// RunPool joins every worker before returning. The caller owns jobs and must
// cancel its own producer when this function returns early. fn must honor ctx
// and must not panic. This pool is an in-process executor, not durable storage.
func RunPool(ctx context.Context, workers int, jobs <-chan int, fn func(context.Context, int) error) error {
	if workers < 1 || fn == nil {
		return errors.New("positive worker count and function required")
	}
	workCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	firstError := make(chan error, 1)
	var wg sync.WaitGroup
	wg.Add(workers)
	for i := 0; i < workers; i++ {
		go func() {
			defer wg.Done()
			for {
				if workCtx.Err() != nil {
					return
				}
				select {
				case <-workCtx.Done():
					return
				case job, ok := <-jobs:
					if !ok {
						return
					}
					if workCtx.Err() != nil {
						return
					}
					if err := fn(workCtx, job); err != nil {
						select {
						case firstError <- err:
						default:
						}
						cancel()
						return
					}
				}
			}
		}()
	}
	wg.Wait()
	select {
	case err := <-firstError:
		return err
	default:
		return ctx.Err()
	}
}
