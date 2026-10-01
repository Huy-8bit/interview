package kafka

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/kmsg"

	"github.com/nghuy8bit/kafka-lab/pkg/config"
	"github.com/nghuy8bit/kafka-lab/pkg/events"
	"github.com/nghuy8bit/kafka-lab/pkg/metrics"
)

// Commit modes (labs/07_offsets, docs/08-offset.md):
//
//	manual          process every record of the poll, THEN commit what was processed (at-least-once)
//	before-process  commit what was polled BEFORE processing it                       (at-most-once)
//	auto            client commits every AUTO_COMMIT_INTERVAL the offsets of the PREVIOUS poll
//	auto-greedy     client commits every interval everything polled so far (may lose on crash)
const (
	CommitManual        = "manual"
	CommitBeforeProcess = "before-process"
	CommitAuto          = "auto"
	CommitAutoGreedy    = "auto-greedy"
)

// HandlerFunc processes one record. Returning an error routes the record to
// the retry topic (or the DLQ when the error is Permanent or retries are exhausted).
type HandlerFunc func(ctx context.Context, rec *kgo.Record) error

type ConsumerConfig struct {
	Service  string
	Instance string
	Group    string
	Topics   []string

	CommitMode         string
	AutoCommitInterval time.Duration
	Balancer           string // cooperative-sticky | sticky | range | roundrobin
	GroupProtocol      string // classic | consumer (KIP-848)
	StaticMembership   bool   // group.instance.id = Instance
	SessionTimeout     time.Duration
	HeartbeatInterval  time.Duration
	RebalanceTimeout   time.Duration
	ResetOffset        string // earliest | latest (only used when the group has no committed offset)
	ReadCommitted      bool

	MaxPollRecords  int
	Concurrency     int // partitions processed in parallel (records within a partition stay sequential)
	ProcessingDelay time.Duration

	InlineRetries int // blocking in-place retries before routing (0 = none)
	RetryTopic    string
	DLQTopic      string
	MaxRetries    int
	RetryBackoff  time.Duration
	RetryStage    bool // this runner consumes a retry topic: wait until retry_not_before

	LogEvery int // log 1 of N successfully processed records (errors are always logged)
}

func ConsumerConfigFromEnv(service string) ConsumerConfig {
	return ConsumerConfig{
		Service:            service,
		Instance:           config.Instance(service),
		Group:              config.String("CONSUMER_GROUP", service+"-group"),
		Topics:             config.List("CONSUMER_TOPICS", "orders"),
		CommitMode:         config.String("COMMIT_MODE", CommitManual),
		AutoCommitInterval: config.Duration("AUTO_COMMIT_INTERVAL", 5*time.Second),
		Balancer:           config.String("BALANCER", "cooperative-sticky"),
		GroupProtocol:      config.String("GROUP_PROTOCOL", "classic"),
		StaticMembership:   config.Bool("STATIC_MEMBERSHIP", false),
		SessionTimeout:     config.Duration("SESSION_TIMEOUT", 45*time.Second),
		HeartbeatInterval:  config.Duration("HEARTBEAT_INTERVAL", 3*time.Second),
		RebalanceTimeout:   config.Duration("REBALANCE_TIMEOUT", 60*time.Second),
		ResetOffset:        config.String("AUTO_OFFSET_RESET", "earliest"),
		ReadCommitted:      config.Bool("READ_COMMITTED", false),
		MaxPollRecords:     config.Int("MAX_POLL_RECORDS", 100),
		Concurrency:        config.Int("CONCURRENCY", 6),
		ProcessingDelay:    time.Duration(config.Int("PROCESSING_DELAY_MS", 0)) * time.Millisecond,
		InlineRetries:      config.Int("INLINE_RETRIES", 0),
		RetryTopic:         config.String("RETRY_TOPIC", ""),
		DLQTopic:           config.String("DLQ_TOPIC", ""),
		MaxRetries:         config.Int("MAX_RETRIES", 3),
		RetryBackoff:       config.Duration("RETRY_BACKOFF", 2*time.Second),
		LogEvery:           config.Int("LOG_EVERY", 1),
	}
}

// RetryStageConfig derives the config of the companion runner that consumes the
// retry topic with its own consumer group (<group>-retry).
func (c ConsumerConfig) RetryStageConfig() ConsumerConfig {
	rc := c
	rc.Group = c.Group + "-retry"
	rc.Topics = []string{c.RetryTopic}
	rc.RetryStage = true
	rc.CommitMode = CommitManual
	rc.ProcessingDelay = 0
	rc.GroupProtocol = "classic"
	rc.Balancer = "cooperative-sticky"
	rc.StaticMembership = false
	return rc
}

func Balancer(name string) (kgo.GroupBalancer, error) {
	switch name {
	case "cooperative-sticky", "":
		return kgo.CooperativeStickyBalancer(), nil
	case "sticky":
		return kgo.StickyBalancer(), nil
	case "range":
		return kgo.RangeBalancer(), nil
	case "roundrobin":
		return kgo.RoundRobinBalancer(), nil
	}
	return nil, fmt.Errorf("unknown balancer %q", name)
}

// Runner is a consumer-group member with explicit, observable commit behaviour.
type Runner struct {
	cfg        ConsumerConfig
	log        *slog.Logger
	handler    HandlerFunc
	AfterBatch func(ctx context.Context) error // optional hook after each poll batch (batch processing)

	cl       *kgo.Client
	delayNs  atomic.Int64
	logEvery atomic.Int64
	running  atomic.Bool
	seen     atomic.Int64

	mu         sync.Mutex
	assigned   map[string][]int32
	pending    map[string]map[int32]kgo.EpochOffset // processed but not yet committed (manual mode)
	lastRevoke time.Time
	generation int
}

func NewRunner(cfg ConsumerConfig, log *slog.Logger, h HandlerFunc) (*Runner, error) {
	r := &Runner{
		cfg:      cfg,
		log:      log.With("consumer", cfg.Instance, "group", cfg.Group),
		handler:  h,
		assigned: map[string][]int32{},
		pending:  map[string]map[int32]kgo.EpochOffset{},
	}
	r.delayNs.Store(int64(cfg.ProcessingDelay))
	r.logEvery.Store(int64(max(cfg.LogEvery, 1)))

	bal, err := Balancer(cfg.Balancer)
	if err != nil {
		return nil, err
	}
	opts := BaseOpts(cfg.Instance, log)
	opts = append(opts,
		kgo.ConsumerGroup(cfg.Group),
		kgo.ConsumeTopics(cfg.Topics...),
		kgo.Balancers(bal),
		kgo.SessionTimeout(cfg.SessionTimeout),
		kgo.HeartbeatInterval(cfg.HeartbeatInterval),
		kgo.RebalanceTimeout(cfg.RebalanceTimeout),
		kgo.OnPartitionsAssigned(r.onAssigned),
		kgo.OnPartitionsRevoked(r.onRevoked),
		kgo.OnPartitionsLost(r.onLost),
		// Do not let a rebalance happen while a polled batch is being processed;
		// we call AllowRebalance() after processing+commit. This is what makes
		// "commit in onRevoked" safe.
		kgo.BlockRebalanceOnPoll(),
		kgo.FetchMaxWait(500*time.Millisecond),
		// producing to retry/DLQ topics uses the same client: acks=all + idempotent (defaults)
	)
	if cfg.ResetOffset == "latest" {
		opts = append(opts, kgo.ConsumeResetOffset(kgo.NewOffset().AtEnd()))
	} else {
		opts = append(opts, kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()))
	}
	if cfg.GroupProtocol == "consumer" {
		// KIP-848: the group coordinator computes the assignment (incremental, no stop-the-world)
		opts = append(opts, kgo.ServerSideBalancer())
	}
	if cfg.StaticMembership {
		opts = append(opts, kgo.InstanceID(cfg.Instance))
	}
	if cfg.ReadCommitted {
		opts = append(opts, kgo.FetchIsolationLevel(kgo.ReadCommitted()))
	}
	switch cfg.CommitMode {
	case CommitManual, CommitBeforeProcess:
		opts = append(opts, kgo.DisableAutoCommit())
	case CommitAuto:
		opts = append(opts, kgo.AutoCommitInterval(cfg.AutoCommitInterval))
	case CommitAutoGreedy:
		opts = append(opts, kgo.AutoCommitInterval(cfg.AutoCommitInterval), kgo.GreedyAutoCommit())
	default:
		return nil, fmt.Errorf("unknown COMMIT_MODE %q", cfg.CommitMode)
	}
	cl, err := kgo.NewClient(opts...)
	if err != nil {
		return nil, err
	}
	r.cl = cl
	return r, nil
}

func (r *Runner) Client() *kgo.Client      { return r.cl }
func (r *Runner) Config() ConsumerConfig   { return r.cfg }
func (r *Runner) SetDelay(d time.Duration) { r.delayNs.Store(int64(d)) }
func (r *Runner) SetLogEvery(n int)        { r.logEvery.Store(int64(max(n, 1))) }
func (r *Runner) Delay() time.Duration     { return time.Duration(r.delayNs.Load()) }
func (r *Runner) Logger() *slog.Logger     { return r.log }
func (r *Runner) Healthy() error {
	if !r.running.Load() {
		return errors.New("consumer loop not running")
	}
	return nil
}

// State is exposed on /admin/state so labs can see assignment + config.
func (r *Runner) State() map[string]any {
	r.mu.Lock()
	defer r.mu.Unlock()
	asg := map[string][]int32{}
	for t, ps := range r.assigned {
		asg[t] = append([]int32(nil), ps...)
	}
	return map[string]any{
		"instance":       r.cfg.Instance,
		"group":          r.cfg.Group,
		"topics":         r.cfg.Topics,
		"assignment":     asg,
		"commit_mode":    r.cfg.CommitMode,
		"balancer":       r.cfg.Balancer,
		"group_protocol": r.cfg.GroupProtocol,
		"delay_ms":       r.Delay().Milliseconds(),
		"log_every":      r.logEvery.Load(),
		"records_seen":   r.seen.Load(),
		"rebalances":     r.generation,
	}
}

// ---------------------------------------------------------------- rebalance callbacks

func fmtAssign(m map[string][]int32) string {
	topics := make([]string, 0, len(m))
	for t := range m {
		topics = append(topics, t)
	}
	sort.Strings(topics)
	var b strings.Builder
	for i, t := range topics {
		ps := append([]int32(nil), m[t]...)
		sort.Slice(ps, func(a, b int) bool { return ps[a] < ps[b] })
		if i > 0 {
			b.WriteByte(' ')
		}
		b.WriteString(t)
		b.WriteString("[")
		for j, p := range ps {
			if j > 0 {
				b.WriteByte(' ')
			}
			b.WriteString("P" + strconv.Itoa(int(p)))
		}
		b.WriteString("]")
	}
	if b.Len() == 0 {
		return "(none)"
	}
	return b.String()
}

func (r *Runner) onAssigned(_ context.Context, _ *kgo.Client, m map[string][]int32) {
	r.mu.Lock()
	r.generation++
	for t, ps := range m {
		r.assigned[t] = mergeParts(r.assigned[t], ps)
	}
	all := fmtAssign(r.assigned)
	var since time.Duration
	if !r.lastRevoke.IsZero() {
		since = time.Since(r.lastRevoke)
	}
	r.updateGaugesLocked()
	r.mu.Unlock()
	metrics.Rebalances.WithLabelValues(r.cfg.Service, r.cfg.Group, "assigned").Inc()
	args := []any{"newly_assigned", fmtAssign(m), "now_owns", all}
	if since > 0 {
		args = append(args, "since_last_revoke", since.Round(time.Millisecond))
	}
	r.log.Info("REBALANCE partitions assigned", args...)
}

func (r *Runner) onRevoked(ctx context.Context, cl *kgo.Client, m map[string][]int32) {
	// Commit what we processed for the partitions we are about to lose, so the
	// next owner starts exactly after our last processed record.
	if r.cfg.CommitMode == CommitManual {
		r.commitPending(ctx, "on-revoke")
	}
	r.mu.Lock()
	r.lastRevoke = time.Now()
	for t, ps := range m {
		r.assigned[t] = removeParts(r.assigned[t], ps)
		if len(r.assigned[t]) == 0 {
			delete(r.assigned, t)
		}
	}
	all := fmtAssign(r.assigned)
	r.updateGaugesLocked()
	r.mu.Unlock()
	metrics.Rebalances.WithLabelValues(r.cfg.Service, r.cfg.Group, "revoked").Inc()
	r.log.Info("REBALANCE partitions revoked", "revoked", fmtAssign(m), "still_owns", all)
}

func (r *Runner) onLost(_ context.Context, _ *kgo.Client, m map[string][]int32) {
	if len(m) == 0 {
		return
	}
	// Lost = we were kicked out (session timeout / fenced). We must NOT commit:
	// another member may already own these partitions.
	r.mu.Lock()
	r.lastRevoke = time.Now()
	for t, ps := range m {
		r.assigned[t] = removeParts(r.assigned[t], ps)
		if len(r.assigned[t]) == 0 {
			delete(r.assigned, t)
		}
		delete(r.pending, t)
	}
	r.updateGaugesLocked()
	r.mu.Unlock()
	metrics.Rebalances.WithLabelValues(r.cfg.Service, r.cfg.Group, "lost").Inc()
	r.log.Warn("REBALANCE partitions LOST (session expired or fenced, not committing)", "lost", fmtAssign(m))
}

func (r *Runner) updateGaugesLocked() {
	for _, t := range r.cfg.Topics {
		metrics.AssignedPartitions.WithLabelValues(r.cfg.Service, r.cfg.Group, t).Set(float64(len(r.assigned[t])))
	}
}

func mergeParts(a, b []int32) []int32 {
	set := map[int32]bool{}
	for _, p := range a {
		set[p] = true
	}
	for _, p := range b {
		set[p] = true
	}
	out := make([]int32, 0, len(set))
	for p := range set {
		out = append(out, p)
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

func removeParts(a, b []int32) []int32 {
	rm := map[int32]bool{}
	for _, p := range b {
		rm[p] = true
	}
	var out []int32
	for _, p := range a {
		if !rm[p] {
			out = append(out, p)
		}
	}
	return out
}

// ---------------------------------------------------------------- main loop

// Run polls until ctx is cancelled, then finishes the current batch, commits
// and leaves the group (graceful shutdown).
func (r *Runner) Run(ctx context.Context) error {
	r.running.Store(true)
	defer r.running.Store(false)
	r.log.Info("consumer started",
		"topics", strings.Join(r.cfg.Topics, ","), "commit_mode", r.cfg.CommitMode,
		"balancer", r.cfg.Balancer, "group_protocol", r.cfg.GroupProtocol,
		"retry_topic", r.cfg.RetryTopic, "dlq_topic", r.cfg.DLQTopic, "max_retries", r.cfg.MaxRetries,
		"processing_delay", r.Delay())

	// Handlers run with a context that is NOT cancelled by SIGTERM so the record
	// currently being processed can finish ("finish current work, then stop").
	procCtx := context.WithoutCancel(ctx)

	for {
		fetches := r.cl.PollRecords(ctx, r.cfg.MaxPollRecords)
		if fetches.IsClientClosed() || ctx.Err() != nil {
			r.cl.AllowRebalance()
			break
		}
		fetches.EachError(func(t string, p int32, err error) {
			if !errors.Is(err, context.Canceled) {
				r.log.Warn("fetch error", "topic", t, "partition", p, "err", err)
			}
		})
		if fetches.NumRecords() == 0 {
			r.cl.AllowRebalance()
			continue
		}

		if r.cfg.CommitMode == CommitBeforeProcess {
			// at-most-once: the offsets are durable BEFORE the work is done.
			if err := r.cl.CommitUncommittedOffsets(procCtx); err != nil {
				metrics.Commits.WithLabelValues(r.cfg.Service, r.cfg.Group, "error").Inc()
				r.log.Error("commit (before-process) failed", "err", err)
			} else {
				metrics.Commits.WithLabelValues(r.cfg.Service, r.cfg.Group, "ok").Inc()
				r.log.Info("COMMIT before processing (at-most-once)", "records", fetches.NumRecords())
			}
		}

		r.processFetches(ctx, procCtx, fetches)

		if r.AfterBatch != nil {
			if err := r.AfterBatch(procCtx); err != nil {
				r.log.Error("after-batch hook failed", "err", err)
			}
		}
		if r.cfg.CommitMode == CommitManual {
			r.commitPending(procCtx, "after-batch")
		}
		r.cl.AllowRebalance()
	}

	r.log.Info("shutdown: stopped polling, committing and leaving group")
	if r.cfg.CommitMode == CommitManual {
		r.commitPending(procCtx, "shutdown")
	}
	r.cl.Close() // leaves the group (LeaveGroup) -> immediate rebalance for the others
	r.log.Info("shutdown: left consumer group cleanly")
	return nil
}

func (r *Runner) processFetches(ctx, procCtx context.Context, fetches kgo.Fetches) {
	conc := r.cfg.Concurrency
	if conc < 1 {
		conc = 1
	}
	sem := make(chan struct{}, conc)
	var wg sync.WaitGroup
	fetches.EachPartition(func(p kgo.FetchTopicPartition) {
		if len(p.Records) == 0 {
			return
		}
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-sem }()
			for _, rec := range p.Records {
				if !r.processRecord(ctx, procCtx, rec, p.HighWatermark) {
					return // aborted (shutdown while waiting): do not mark later records
				}
				r.markProcessed(rec)
			}
		}()
	})
	wg.Wait()
}

func (r *Runner) markProcessed(rec *kgo.Record) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.pending[rec.Topic] == nil {
		r.pending[rec.Topic] = map[int32]kgo.EpochOffset{}
	}
	// committed offset = offset of the NEXT record to read
	r.pending[rec.Topic][rec.Partition] = kgo.EpochOffset{Epoch: rec.LeaderEpoch, Offset: rec.Offset + 1}
}

func (r *Runner) commitPending(ctx context.Context, reason string) {
	r.mu.Lock()
	if len(r.pending) == 0 {
		r.mu.Unlock()
		return
	}
	toCommit := r.pending
	r.pending = map[string]map[int32]kgo.EpochOffset{}
	r.mu.Unlock()

	var commitErr error
	r.cl.CommitOffsetsSync(ctx, toCommit, func(_ *kgo.Client, _ *kmsg.OffsetCommitRequest, resp *kmsg.OffsetCommitResponse, err error) {
		if err != nil {
			commitErr = err
			return
		}
		for _, t := range resp.Topics {
			for _, p := range t.Partitions {
				if p.ErrorCode != 0 {
					commitErr = fmt.Errorf("%s[%d]: error code %d", t.Topic, p.Partition, p.ErrorCode)
				}
			}
		}
	})
	if commitErr != nil {
		metrics.Commits.WithLabelValues(r.cfg.Service, r.cfg.Group, "error").Inc()
		r.log.Error("offset commit failed (records will be redelivered)", "reason", reason, "err", commitErr)
		return
	}
	metrics.Commits.WithLabelValues(r.cfg.Service, r.cfg.Group, "ok").Inc()
	var parts []string
	for t, ps := range toCommit {
		for p, eo := range ps {
			parts = append(parts, fmt.Sprintf("%s/P%d=%d", t, p, eo.Offset))
		}
	}
	sort.Strings(parts)
	r.log.Debug("COMMIT offsets", "reason", reason, "offsets", strings.Join(parts, " "))
}

// processRecord returns false if processing was aborted by shutdown.
func (r *Runner) processRecord(ctx, procCtx context.Context, rec *kgo.Record, hw int64) bool {
	n := r.seen.Add(1)
	attempt := Attempt(rec)

	if r.cfg.RetryStage {
		if nb := HeaderInt(rec, events.HeaderRetryNotBefore, 0); nb > 0 {
			if wait := time.Until(time.UnixMilli(nb)); wait > 0 {
				select {
				case <-ctx.Done():
					return false
				case <-time.After(wait):
				}
			}
		}
	}
	if d := r.Delay(); d > 0 {
		time.Sleep(d) // simulated slow processing (backpressure lab)
	}

	start := time.Now()
	err := r.handler(procCtx, rec)
	for i := 1; err != nil && i <= r.cfg.InlineRetries && !IsPermanent(err); i++ {
		r.log.Warn("inline retry", "topic", rec.Topic, "partition", rec.Partition, "offset", rec.Offset, "try", i, "err", err)
		time.Sleep(time.Duration(i) * 200 * time.Millisecond)
		err = r.handler(procCtx, rec)
	}
	dur := time.Since(start)

	partLabel := strconv.Itoa(int(rec.Partition))
	metrics.Consumed.WithLabelValues(r.cfg.Service, r.cfg.Group, rec.Topic, partLabel).Inc()
	metrics.ProcessingDuration.WithLabelValues(r.cfg.Service, r.cfg.Group, rec.Topic).Observe(dur.Seconds())
	metrics.EndToEndLatency.WithLabelValues(r.cfg.Service, r.cfg.Group, rec.Topic).Observe(time.Since(rec.Timestamp).Seconds())

	evType, _ := Header(rec, events.HeaderEventType)
	if err == nil {
		if every := r.logEvery.Load(); every <= 1 || n%every == 0 {
			args := []any{"topic", rec.Topic, "partition", rec.Partition, "offset", rec.Offset,
				"key", string(rec.Key), "event_type", evType, "hw", hw, "lag", hw - rec.Offset - 1, "took", dur}
			if attempt > 0 {
				args = append(args, "attempt", attempt)
			}
			r.log.Info("processed", args...)
		}
		return true
	}

	metrics.ConsumeErrors.WithLabelValues(r.cfg.Service, r.cfg.Group, rec.Topic).Inc()
	r.routeFailure(procCtx, rec, err)
	return true
}

// routeFailure sends a failed record to the retry topic or the DLQ. If that
// produce cannot succeed we crash on purpose: skipping the record would be
// silent data loss, a restart re-reads it from the last committed offset.
func (r *Runner) routeFailure(ctx context.Context, rec *kgo.Record, cause error) {
	attempt := Attempt(rec) // failures before this one
	next := attempt + 1
	origin := OriginOf(rec)
	base := []any{"topic", rec.Topic, "partition", rec.Partition, "offset", rec.Offset, "key", string(rec.Key),
		"origin", fmt.Sprintf("%s/P%d@%d", origin.Topic, origin.Partition, origin.Offset), "err", cause.Error()}

	var out *kgo.Record
	var kind string
	switch {
	case !IsPermanent(cause) && r.cfg.RetryTopic != "" && attempt < r.cfg.MaxRetries:
		backoff := r.cfg.RetryBackoff * time.Duration(1<<attempt) // 2s, 4s, 8s ...
		out = BuildFailureRecord(rec, r.cfg.RetryTopic, next, cause, r.cfg.Group, r.cfg.Instance, time.Now().Add(backoff))
		kind = "retry"
		r.log.Warn(fmt.Sprintf("FAILED -> %s (attempt %d/%d, backoff %s)", r.cfg.RetryTopic, next, r.cfg.MaxRetries, backoff), base...)
	case r.cfg.DLQTopic != "":
		out = BuildFailureRecord(rec, r.cfg.DLQTopic, next, cause, r.cfg.Group, r.cfg.Instance, time.Time{})
		kind = "dlq"
		why := "retries exhausted"
		if IsPermanent(cause) {
			why = "non-retryable error"
		}
		r.log.Error(fmt.Sprintf("FAILED -> %s (%s after %d attempt(s))", r.cfg.DLQTopic, why, next), base...)
	default:
		r.log.Error("FAILED with no retry/DLQ topic configured: stopping the line (crash) so the record is not skipped", base...)
		os.Exit(3)
	}

	for i := 0; ; i++ {
		_, err := ProduceSync(ctx, r.cl, r.cfg.Service, out)
		if err == nil {
			break
		}
		if i >= 10 {
			r.log.Error("cannot route failed record, crashing to avoid losing it", "dst", out.Topic, "err", err)
			os.Exit(2)
		}
		time.Sleep(time.Second)
	}
	if kind == "retry" {
		metrics.Retries.WithLabelValues(r.cfg.Service, r.cfg.Group, origin.Topic).Inc()
	} else {
		metrics.DLQ.WithLabelValues(r.cfg.Service, r.cfg.Group, origin.Topic).Inc()
	}
}
