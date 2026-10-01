package kafka

import (
	"errors"
	"strconv"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/events"
)

func Header(r *kgo.Record, key string) (string, bool) {
	// last value wins (headers may be appended on every retry hop)
	for i := len(r.Headers) - 1; i >= 0; i-- {
		if r.Headers[i].Key == key {
			return string(r.Headers[i].Value), true
		}
	}
	return "", false
}

func HeaderInt(r *kgo.Record, key string, def int64) int64 {
	if v, ok := Header(r, key); ok {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	return def
}

func SetHeader(r *kgo.Record, key, value string) {
	for i := range r.Headers {
		if r.Headers[i].Key == key {
			r.Headers[i].Value = []byte(value)
			return
		}
	}
	r.Headers = append(r.Headers, kgo.RecordHeader{Key: key, Value: []byte(value)})
}

// Attempt returns how many times this record has already failed (0 on the main topic).
func Attempt(r *kgo.Record) int { return int(HeaderInt(r, events.HeaderAttempt, 0)) }

// FailureMeta describes where a failing record originally came from.
type FailureMeta struct {
	Topic     string
	Partition int32
	Offset    int64
	Timestamp time.Time
}

// OriginOf returns the ORIGINAL coordinates: for a record already in a retry
// topic those come from headers, otherwise from the record itself.
func OriginOf(r *kgo.Record) FailureMeta {
	if t, ok := Header(r, events.HeaderOriginalTopic); ok {
		return FailureMeta{
			Topic:     t,
			Partition: int32(HeaderInt(r, events.HeaderOriginalPartition, -1)),
			Offset:    HeaderInt(r, events.HeaderOriginalOffset, -1),
			Timestamp: time.UnixMilli(HeaderInt(r, events.HeaderOriginalTimestamp, 0)),
		}
	}
	return FailureMeta{Topic: r.Topic, Partition: r.Partition, Offset: r.Offset, Timestamp: r.Timestamp}
}

// BuildFailureRecord copies key/value/headers of a failed record into a new
// record for the retry or DLQ topic and stamps the failure metadata.
func BuildFailureRecord(src *kgo.Record, dstTopic string, attempt int, cause error, group, instance string, notBefore time.Time) *kgo.Record {
	origin := OriginOf(src)
	out := &kgo.Record{Topic: dstTopic, Key: src.Key, Value: src.Value}
	out.Headers = append(out.Headers, src.Headers...)
	SetHeader(out, events.HeaderAttempt, strconv.Itoa(attempt))
	SetHeader(out, events.HeaderOriginalTopic, origin.Topic)
	SetHeader(out, events.HeaderOriginalPartition, strconv.Itoa(int(origin.Partition)))
	SetHeader(out, events.HeaderOriginalOffset, strconv.FormatInt(origin.Offset, 10))
	SetHeader(out, events.HeaderOriginalTimestamp, strconv.FormatInt(origin.Timestamp.UnixMilli(), 10))
	SetHeader(out, events.HeaderError, truncate(cause.Error(), 500))
	SetHeader(out, events.HeaderFailedAt, time.Now().UTC().Format(time.RFC3339Nano))
	SetHeader(out, events.HeaderFailedGroup, group)
	SetHeader(out, events.HeaderFailedBy, instance)
	if !notBefore.IsZero() {
		SetHeader(out, events.HeaderRetryNotBefore, strconv.FormatInt(notBefore.UnixMilli(), 10))
	}
	return out
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// permanentError marks failures that must skip the retry topic and go straight
// to the DLQ (e.g. undeserializable payloads: retrying can never succeed).
type permanentError struct{ err error }

func (p permanentError) Error() string { return "permanent: " + p.err.Error() }
func (p permanentError) Unwrap() error { return p.err }

func Permanent(err error) error { return permanentError{err} }

func IsPermanent(err error) bool {
	var p permanentError
	return errors.As(err, &p)
}
