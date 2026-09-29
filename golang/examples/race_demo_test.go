//go:build racedemo

package labs

import (
	"sync"
	"testing"
)

// This negative test intentionally fails under -race. It is excluded by default.
func TestIntentionalRace(t *testing.T) {
	var n int
	var wg sync.WaitGroup
	wg.Add(2)
	for i := 0; i < 2; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < 10000; j++ {
				n++
			}
		}()
	}
	wg.Wait()
	t.Log(n)
}
