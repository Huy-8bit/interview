// txn-processor: exactly-once "consume -> process -> produce" inside Kafka
// using a transactional producer + consumer group (franz-go GroupTransactSession).
//
//	txn-input  --(read_committed, group txn-processor-group)-->  process  --> txn-output
//
// One transaction contains:
//  1. the output records (txn-output)
//  2. the consumer offsets of the input records (TxnOffsetCommit -> __consumer_offsets)
//
// Either both become visible (commit) or neither (abort). A read_committed
// consumer of txn-output never sees records of an aborted transaction.
//
// Lab hook: an input with lab_fault=abort_txn makes the FIRST attempt abort
// after the output was already written. The session rewinds to the last
// committed offset and the record is processed again, this time committed:
// read_uncommitted readers see the output twice, read_committed readers once.
package main

import (
	"context"
	"encoding/json"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/app"
	"github.com/nghuy8bit/kafka-lab/pkg/config"
	"github.com/nghuy8bit/kafka-lab/pkg/events"
	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
	"github.com/nghuy8bit/kafka-lab/pkg/logging"
	"github.com/nghuy8bit/kafka-lab/pkg/metrics"
)

const service = "txn-processor"

func main() {
	log := logging.New(service)
	ctx, stop := app.SignalContext()
	defer stop()

	instance := config.Instance(service)
	group := config.String("CONSUMER_GROUP", "txn-processor-group")
	in := config.String("INPUT_TOPIC", "txn-input")
	out := config.String("OUTPUT_TOPIC", "txn-output")
	// transactional.id must be stable across restarts of the SAME logical producer:
	// on restart InitProducerId bumps the epoch and fences the zombie instance.
	txnID := config.String("TRANSACTIONAL_ID", "txn-processor-"+instance)

	opts := kafka.BaseOpts(instance, log)
	opts = append(opts,
		kgo.TransactionalID(txnID),
		kgo.TransactionTimeout(30*time.Second),
		kgo.ConsumerGroup(group),
		kgo.ConsumeTopics(in),
		kgo.FetchIsolationLevel(kgo.ReadCommitted()),
		kgo.RequireStableFetchOffsets(),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()),
		kgo.SessionTimeout(10*time.Second),
		kgo.HeartbeatInterval(time.Second),
		kgo.OnPartitionsAssigned(func(_ context.Context, _ *kgo.Client, m map[string][]int32) {
			log.Info("REBALANCE partitions assigned", "assigned", m)
		}),
	)
	sess, err := kgo.NewGroupTransactSession(opts...)
	if err != nil {
		log.Error("cannot create transactional session", "err", err)
		os.Exit(1)
	}

	aborted := map[string]bool{} // event ids already aborted once (in-memory, lab only)

	srv := metrics.NewServer(config.String("HTTP_ADDR", ":8080"))
	srv.SetHealth(func() error {
		hctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		return sess.Client().Ping(hctx)
	})
	srv.Start(log)
	log.Info("transactional processor started", "transactional_id", txnID, "input", in, "output", out, "group", group)

	for {
		fetches := sess.PollFetches(ctx)
		if fetches.IsClientClosed() || ctx.Err() != nil {
			break
		}
		fetches.EachError(func(t string, p int32, err error) { log.Warn("fetch error", "topic", t, "partition", p, "err", err) })
		recs := fetches.Records()
		if len(recs) == 0 {
			continue
		}

		if err := sess.Begin(); err != nil {
			log.Error("begin transaction failed", "err", err)
			continue
		}
		commit := kgo.TryCommit
		var ids []string
		for _, rec := range recs {
			var ev events.OrderEvent
			if err := json.Unmarshal(rec.Value, &ev); err != nil {
				log.Warn("skipping undeserializable record", "partition", rec.Partition, "offset", rec.Offset)
				continue
			}
			ids = append(ids, ev.OrderID)
			ev.Status = "VALIDATED"
			ev.EventType = "OrderValidated"
			val, _ := json.Marshal(ev)
			sess.Produce(ctx, &kgo.Record{Topic: out, Key: rec.Key, Value: val, Headers: []kgo.RecordHeader{
				{Key: events.HeaderEventType, Value: []byte("OrderValidated")},
				{Key: "source_offset", Value: []byte(rec.Topic + "/" + strconv.Itoa(int(rec.Partition)) + "@" + strconv.FormatInt(rec.Offset, 10))},
			}}, func(r *kgo.Record, err error) {
				if err != nil {
					log.Error("transactional produce failed", "err", err)
				}
			})
			if ev.LabFault == events.FaultAbortTxn && !aborted[ev.EventID] {
				aborted[ev.EventID] = true
				commit = kgo.TryAbort
			}
		}
		if commit == kgo.TryAbort {
			// Make sure the outputs really reach the log before aborting, so the lab can
			// see them with read_uncommitted. Without a flush, records still sitting in the
			// producer buffer are simply dropped client side and never written.
			if err := sess.Client().Flush(ctx); err != nil {
				log.Warn("flush before abort failed", "err", err)
			}
		}
		committed, err := sess.End(ctx, commit)
		switch {
		case err != nil:
			log.Error("end transaction failed (session will rewind and retry)", "err", err)
		case committed:
			metrics.Produced.WithLabelValues(service, out).Add(float64(len(ids)))
			log.Info("TXN COMMITTED: outputs + input offsets atomically", "records", len(recs), "orders", strings.Join(ids, ","))
		default:
			log.Warn("TXN ABORTED: outputs invisible to read_committed, offsets rewound -> will reprocess",
				"records", len(recs), "orders", strings.Join(ids, ","))
		}
	}
	log.Info("shutdown: closing transactional session")
	sess.Close()
	sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(sctx)
}
