// Package kafka contains the franz-go based building blocks shared by every
// service: client/producer options built from env, a consumer-group runner with
// manual/auto commit, retry and DLQ routing, and record header helpers.
package kafka

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/config"
	"github.com/nghuy8bit/kafka-lab/pkg/metrics"
)

// kgoLogger adapts franz-go's internal logs to slog. Level is controlled by
// KGO_LOG_LEVEL (default warn). Set KGO_LOG_LEVEL=info to see the client's own
// view of group joins, metadata refreshes, leader changes, retries...
type kgoLogger struct {
	l     *slog.Logger
	level kgo.LogLevel
}

func (k kgoLogger) Level() kgo.LogLevel { return k.level }
func (k kgoLogger) Log(level kgo.LogLevel, msg string, keyvals ...any) {
	switch level {
	case kgo.LogLevelError:
		k.l.Error("kgo: "+msg, keyvals...)
	case kgo.LogLevelWarn:
		k.l.Warn("kgo: "+msg, keyvals...)
	case kgo.LogLevelInfo:
		k.l.Info("kgo: "+msg, keyvals...)
	default:
		k.l.Debug("kgo: "+msg, keyvals...)
	}
}

func KgoLogger(l *slog.Logger) kgo.Logger {
	lvl := kgo.LogLevelWarn
	switch strings.ToLower(config.String("KGO_LOG_LEVEL", "warn")) {
	case "debug":
		lvl = kgo.LogLevelDebug
	case "info":
		lvl = kgo.LogLevelInfo
	case "error":
		lvl = kgo.LogLevelError
	case "none":
		lvl = kgo.LogLevelNone
	}
	return kgoLogger{l: l, level: lvl}
}

// BaseOpts are the options every client uses: seed brokers, client.id, logger.
// Only the seed list is needed — the client discovers every broker (and which
// one leads which partition) from the Metadata response.
func BaseOpts(clientID string, log *slog.Logger) []kgo.Opt {
	return []kgo.Opt{
		kgo.SeedBrokers(config.Brokers()...),
		kgo.ClientID(clientID),
		kgo.WithLogger(KgoLogger(log)),
		kgo.MetadataMaxAge(30 * time.Second),
	}
}

// ProducerConfig captures the producer knobs explored in the labs.
type ProducerConfig struct {
	Acks            string        // "0" | "1" | "all"
	Idempotent      bool          // enable.idempotence (requires acks=all)
	Compression     string        // none | gzip | snappy | lz4 | zstd
	Linger          time.Duration // linger.ms
	BatchMaxBytes   int32         // batch.size (per partition batch upper bound)
	Partitioner     string        // sticky (default, murmur2 for keys) | roundrobin | uniform
	RecordRetries   int           // <0 = unlimited (bounded by DeliveryTimeout)
	DeliveryTimeout time.Duration // delivery.timeout.ms (0 = unlimited)
	RequestTimeout  time.Duration // request.timeout.ms analogue (broker side produce timeout)
	TransactionalID string
}

// ProducerConfigFromEnv reads PRODUCER_* env vars.
func ProducerConfigFromEnv() ProducerConfig {
	return ProducerConfig{
		Acks:            config.String("PRODUCER_ACKS", "all"),
		Idempotent:      config.Bool("PRODUCER_IDEMPOTENT", true),
		Compression:     config.String("PRODUCER_COMPRESSION", "lz4"),
		Linger:          time.Duration(config.Int("PRODUCER_LINGER_MS", 5)) * time.Millisecond,
		BatchMaxBytes:   int32(config.Int("PRODUCER_BATCH_MAX_BYTES", 1<<20)),
		Partitioner:     config.String("PRODUCER_PARTITIONER", "sticky"),
		RecordRetries:   config.Int("PRODUCER_RETRIES", -1),
		DeliveryTimeout: config.Duration("PRODUCER_DELIVERY_TIMEOUT", 2*time.Minute),
		RequestTimeout:  config.Duration("PRODUCER_REQUEST_TIMEOUT", 30*time.Second),
	}
}

func ParseAcks(s string) (kgo.Acks, error) {
	switch strings.ToLower(s) {
	case "0", "none":
		return kgo.NoAck(), nil
	case "1", "leader":
		return kgo.LeaderAck(), nil
	case "all", "-1":
		return kgo.AllISRAcks(), nil
	}
	return kgo.AllISRAcks(), fmt.Errorf("unknown acks %q (0|1|all)", s)
}

func ParseCompression(s string) (kgo.CompressionCodec, error) {
	switch strings.ToLower(s) {
	case "", "none":
		return kgo.NoCompression(), nil
	case "gzip":
		return kgo.GzipCompression(), nil
	case "snappy":
		return kgo.SnappyCompression(), nil
	case "lz4":
		return kgo.Lz4Compression(), nil
	case "zstd":
		return kgo.ZstdCompression(), nil
	}
	return kgo.NoCompression(), fmt.Errorf("unknown compression %q", s)
}

// Opts converts the config into franz-go options.
func (c ProducerConfig) Opts() ([]kgo.Opt, error) {
	acks, err := ParseAcks(c.Acks)
	if err != nil {
		return nil, err
	}
	codec, err := ParseCompression(c.Compression)
	if err != nil {
		return nil, err
	}
	opts := []kgo.Opt{
		kgo.RequiredAcks(acks),
		kgo.ProducerBatchCompression(codec),
		kgo.ProducerLinger(c.Linger),
	}
	if c.BatchMaxBytes > 0 {
		opts = append(opts, kgo.ProducerBatchMaxBytes(c.BatchMaxBytes))
	}
	// Idempotence needs acks=all: the broker can only de-duplicate retries of a
	// batch it is guaranteed to have fully replicated.
	if !c.Idempotent || c.Acks != "all" {
		opts = append(opts, kgo.DisableIdempotentWrite())
	}
	switch c.Partitioner {
	case "", "sticky":
		// keyed records: murmur2(key) % partitions (same as the Java client)
		// null key: stick to one partition until the batch is sent (KIP-480)
		opts = append(opts, kgo.RecordPartitioner(kgo.StickyKeyPartitioner(nil)))
	case "roundrobin":
		// ignores keys! breaks per-key ordering — only for demonstrations
		opts = append(opts, kgo.RecordPartitioner(kgo.RoundRobinPartitioner()))
	case "uniform":
		// KIP-794 "uniform sticky": switch partition every ~64KB, adaptive to broker latency
		opts = append(opts, kgo.RecordPartitioner(kgo.UniformBytesPartitioner(64<<10, true, true, nil)))
	default:
		return nil, fmt.Errorf("unknown partitioner %q", c.Partitioner)
	}
	if c.RecordRetries >= 0 {
		opts = append(opts, kgo.RecordRetries(c.RecordRetries))
	}
	if c.DeliveryTimeout > 0 {
		opts = append(opts, kgo.RecordDeliveryTimeout(c.DeliveryTimeout))
	}
	if c.RequestTimeout > 0 {
		opts = append(opts, kgo.ProduceRequestTimeout(c.RequestTimeout))
	}
	if c.TransactionalID != "" {
		opts = append(opts, kgo.TransactionalID(c.TransactionalID))
	}
	return opts, nil
}

func (c ProducerConfig) String() string {
	idem := c.Idempotent && c.Acks == "all"
	return fmt.Sprintf("acks=%s idempotent=%t compression=%s linger=%s batch.max.bytes=%d partitioner=%s",
		c.Acks, idem, c.Compression, c.Linger, c.BatchMaxBytes, c.Partitioner)
}

// NewProducer creates a producer-only client.
func NewProducer(clientID string, pc ProducerConfig, log *slog.Logger, extra ...kgo.Opt) (*kgo.Client, error) {
	popts, err := pc.Opts()
	if err != nil {
		return nil, err
	}
	opts := append(BaseOpts(clientID, log), popts...)
	opts = append(opts, extra...)
	return kgo.NewClient(opts...)
}

// ProduceSync produces one record, waits for the ack and records metrics.
func ProduceSync(ctx context.Context, cl *kgo.Client, service string, r *kgo.Record) (*kgo.Record, error) {
	start := time.Now()
	res := cl.ProduceSync(ctx, r)
	rec, err := res.First()
	observeProduce(service, r.Topic, start, err)
	return rec, err
}

// ProduceAsync produces without waiting; cb (optional) runs after the ack.
func ProduceAsync(ctx context.Context, cl *kgo.Client, service string, r *kgo.Record, cb func(*kgo.Record, error)) {
	start := time.Now()
	cl.Produce(ctx, r, func(rec *kgo.Record, err error) {
		observeProduce(service, r.Topic, start, err)
		if cb != nil {
			cb(rec, err)
		}
	})
}

func observeProduce(service, topic string, start time.Time, err error) {
	if err != nil {
		metrics.ProduceErrors.WithLabelValues(service, topic, ErrorCode(err)).Inc()
		return
	}
	metrics.Produced.WithLabelValues(service, topic).Inc()
	metrics.ProduceLatency.WithLabelValues(service, topic).Observe(time.Since(start).Seconds())
}

// ErrorCode shortens an error into a low-cardinality label value.
func ErrorCode(err error) string {
	s := err.Error()
	if i := strings.IndexByte(s, ':'); i > 0 && i < 48 {
		s = s[:i]
	}
	if len(s) > 48 {
		s = s[:48]
	}
	return s
}
