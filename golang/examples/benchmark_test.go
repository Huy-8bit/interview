package labs

import (
	"strconv"
	"testing"
)

var encoded string

func BenchmarkFormat(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		encoded = strconv.Itoa(i)
	}
}
func FuzzDecimalRoundTrip(f *testing.F) {
	f.Add(int64(0))
	f.Add(int64(-42))
	f.Add(int64(9223372036854775807))
	f.Fuzz(func(t *testing.T, n int64) {
		s := strconv.FormatInt(n, 10)
		got, err := strconv.ParseInt(s, 10, 64)
		if err != nil || got != n {
			t.Fatalf("round trip %d -> %q -> %d: %v", n, s, got, err)
		}
	})
}
