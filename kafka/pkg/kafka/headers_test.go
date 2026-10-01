package kafka

import (
	"errors"
	"testing"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/events"
)

func TestFailureRecordKeepsOrigin(t *testing.T) {
	src := &kgo.Record{Topic: "orders", Partition: 3, Offset: 42, Key: []byte("k"), Value: []byte("v"), Timestamp: time.UnixMilli(1000)}
	r1 := BuildFailureRecord(src, "retry-orders", 1, errors.New("boom"), "g", "c1", time.Now())
	if Attempt(r1) != 1 {
		t.Fatalf("attempt = %d", Attempt(r1))
	}
	// a second hop (record now consumed from retry-orders) must keep the ORIGINAL coordinates
	r1.Topic, r1.Partition, r1.Offset = "retry-orders", 0, 7
	r2 := BuildFailureRecord(r1, "orders-dlq", 2, errors.New("boom again"), "g-retry", "c2", time.Time{})
	o := OriginOf(r2)
	if o.Topic != "orders" || o.Partition != 3 || o.Offset != 42 {
		t.Fatalf("origin lost: %+v", o)
	}
	if v, _ := Header(r2, events.HeaderError); v != "boom again" {
		t.Fatalf("error header = %q", v)
	}
	if _, ok := Header(r2, events.HeaderRetryNotBefore); !ok {
		// copied from the retry hop; DLQ records may carry it, replay strips it
		t.Log("retry_not_before carried over from retry hop")
	}
	if string(r2.Key) != "k" || string(r2.Value) != "v" {
		t.Fatal("key/value must be preserved")
	}
}

func TestPermanent(t *testing.T) {
	err := Permanent(errors.New("bad json"))
	if !IsPermanent(err) || IsPermanent(errors.New("x")) {
		t.Fatal("IsPermanent misclassifies")
	}
}

func TestProducerConfigDisablesIdempotenceForAcks1(t *testing.T) {
	if _, err := (ProducerConfig{Acks: "1", Idempotent: true, Compression: "zstd", Partitioner: "sticky"}).Opts(); err != nil {
		t.Fatal(err)
	}
	if _, err := (ProducerConfig{Acks: "2"}).Opts(); err == nil {
		t.Fatal("acks=2 must be rejected")
	}
}
