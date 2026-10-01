package main

import (
	"fmt"
	"testing"

	"github.com/twmb/franz-go/pkg/kgo"
)

// Our murmur2 must map keys exactly like the client's partitioner (Kafka's default).
func TestMurmur2MatchesFranzGo(t *testing.T) {
	p := kgo.StickyKeyPartitioner(nil).ForTopic("t")
	for i := 0; i < 2000; i++ {
		key := []byte(fmt.Sprintf("order-%d", i))
		for _, n := range []int{1, 3, 6, 12, 50} {
			want := p.Partition(&kgo.Record{Key: key}, n)
			got := int((murmur2(key) & 0x7fffffff) % int32(n))
			if got != want {
				t.Fatalf("key %s n=%d: murmur2 %d, franz-go %d", key, n, got, want)
			}
		}
	}
}

// Known values printed by labs/03 (Java client compatible).
func TestMurmur2KnownValues(t *testing.T) {
	cases := map[string]int32{"order-100": -955961047, "order-101": 1112104930, "user-1002": 494644997}
	for k, want := range cases {
		if got := murmur2([]byte(k)); got != want {
			t.Errorf("murmur2(%q) = %d, want %d", k, got, want)
		}
	}
}
