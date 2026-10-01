package main

import (
	"context"
	"flag"
	"fmt"
	"strconv"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/events"
	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
)

func init() {
	register("dlq-inspect", "print DLQ records with their failure metadata headers", cmdDLQInspect)
	register("dlq-replay", "replay DLQ records (to the group's retry topic by default) exactly once per DLQ offset", cmdDLQReplay)
}

var dlqToRetry = map[string]string{"orders-dlq": "retry-orders", "payments-dlq": "retry-payments"}

func hdr(r *kgo.Record, k string) string {
	v, _ := kafka.Header(r, k)
	return v
}

func printDLQRecord(r *kgo.Record) {
	fmt.Printf("%s P%d @%d key=%s\n", r.Topic, r.Partition, r.Offset, string(r.Key))
	fmt.Printf("    origin     : %s/P%s@%s   failed_group=%s failed_by=%s\n",
		hdr(r, events.HeaderOriginalTopic), hdr(r, events.HeaderOriginalPartition), hdr(r, events.HeaderOriginalOffset),
		hdr(r, events.HeaderFailedGroup), hdr(r, events.HeaderFailedBy))
	fmt.Printf("    attempts   : %s   failed_at=%s\n", hdr(r, events.HeaderAttempt), hdr(r, events.HeaderFailedAt))
	fmt.Printf("    error      : %s\n", hdr(r, events.HeaderError))
	if rc := hdr(r, events.HeaderReplayCount); rc != "" {
		fmt.Printf("    replayed   : %s time(s) before\n", rc)
	}
	fmt.Printf("    value      : %s\n", trunc(string(r.Value), 200))
}

func cmdDLQInspect(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("dlq-inspect", flag.ExitOnError)
	dlq := fs.String("dlq", "orders-dlq", "DLQ topic")
	_ = fs.Parse(args)
	cl, err := newClient(kgo.ConsumeTopics(*dlq), kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()), kgo.FetchMaxWait(300*time.Millisecond))
	if err != nil {
		return err
	}
	defer cl.Close()
	n := 0
	for {
		pctx, cancel := context.WithTimeout(ctx, 3*time.Second)
		f := cl.PollFetches(pctx)
		cancel()
		if f.NumRecords() == 0 {
			break
		}
		f.EachRecord(func(r *kgo.Record) { n++; printDLQRecord(r) })
	}
	fmt.Printf("-- %d record(s) in %s\n", n, *dlq)
	return nil
}

func cmdDLQReplay(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("dlq-replay", flag.ExitOnError)
	dlq := fs.String("dlq", "orders-dlq", "DLQ topic")
	to := fs.String("to", "retry", "retry (the failed group's retry topic) | original | <topic>")
	group := fs.String("group", "", "replayer consumer group (default dlq-replayer-<dlq>): remembers what was replayed")
	key := fs.String("key", "", "only replay records with this key")
	maxN := fs.Int("max", 0, "replay at most N records (0 = all pending)")
	dry := fs.Bool("dry-run", false, "print what would be replayed, commit nothing")
	_ = fs.Parse(args)
	if *group == "" {
		*group = "dlq-replayer-" + *dlq
	}
	// A filtered replay (-key) must not record progress: committing would also
	// mark the SKIPPED records as replayed. It reads the whole DLQ without a group.
	useGroup := *key == ""
	opts := []kgo.Opt{kgo.ConsumeTopics(*dlq), kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()), kgo.FetchMaxWait(300 * time.Millisecond)}
	if useGroup {
		opts = append(opts, kgo.ConsumerGroup(*group), kgo.DisableAutoCommit())
	}
	cl, err := newClient(opts...)
	if err != nil {
		return err
	}
	defer cl.Close()

	replayed, skipped := 0, 0
	for {
		pctx, cancel := context.WithTimeout(ctx, 4*time.Second)
		f := cl.PollFetches(pctx)
		cancel()
		if f.NumRecords() == 0 {
			break
		}
		var done []*kgo.Record
		stop := false
		f.EachRecord(func(r *kgo.Record) {
			if stop {
				return
			}
			if *key != "" && string(r.Key) != *key {
				skipped++
				done = append(done, r)
				return
			}
			target := *to
			switch *to {
			case "retry":
				target = dlqToRetry[*dlq]
				if target == "" {
					target = hdr(r, events.HeaderOriginalTopic)
				}
			case "original":
				target = hdr(r, events.HeaderOriginalTopic)
			}
			out := &kgo.Record{Topic: target, Key: r.Key, Value: r.Value}
			for _, h := range r.Headers {
				switch h.Key {
				case events.HeaderRetryNotBefore, events.HeaderAttempt, events.HeaderReplayed, events.HeaderReplayCount:
					continue
				}
				if *to == "original" && (h.Key == events.HeaderOriginalTopic || h.Key == events.HeaderOriginalPartition ||
					h.Key == events.HeaderOriginalOffset || h.Key == events.HeaderOriginalTimestamp) {
					continue
				}
				out.Headers = append(out.Headers, h)
			}
			rc, _ := strconv.Atoi(hdr(r, events.HeaderReplayCount))
			kafka.SetHeader(out, events.HeaderAttempt, "0")
			kafka.SetHeader(out, events.HeaderReplayed, fmt.Sprintf("%s/P%d@%d", r.Topic, r.Partition, r.Offset))
			kafka.SetHeader(out, events.HeaderReplayCount, strconv.Itoa(rc+1))
			fmt.Printf("replay %s P%d @%d key=%s -> %s (replay #%d)\n", r.Topic, r.Partition, r.Offset, string(r.Key), target, rc+1)
			if !*dry {
				if _, err := cl.ProduceSync(ctx, out).First(); err != nil {
					fmt.Println("    produce failed, stopping:", err)
					stop = true
					return
				}
			}
			replayed++
			done = append(done, r)
			if *maxN > 0 && replayed >= *maxN {
				stop = true
			}
		})
		if useGroup && !*dry && len(done) > 0 {
			if err := cl.CommitRecords(ctx, done...); err != nil {
				return fmt.Errorf("commit replay progress: %w", err)
			}
		}
		if stop || *dry {
			break
		}
	}
	switch {
	case *dry:
		fmt.Printf("-- DRY RUN: would replay %d, skipped %d; nothing produced or committed\n", replayed, skipped)
	case useGroup:
		fmt.Printf("-- replayed %d record(s); group %s remembers progress (next run replays only newer DLQ records)\n", replayed, *group)
	default:
		fmt.Printf("-- replayed %d record(s) matching key %q, skipped %d; filtered replay records no progress\n", replayed, *key, skipped)
	}
	return nil
}
