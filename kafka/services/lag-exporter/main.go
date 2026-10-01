// lag-exporter: reads cluster state through the Kafka Admin API every
// SCRAPE_INTERVAL and exposes it as Prometheus metrics.
//
// Consumer lag is NOT a broker metric: it is computed client side as
//
//	lag(group, partition) = log end offset (high watermark) - committed offset(group)
//
// which is exactly what `kafka-consumer-groups.sh --describe` does.
//
//	kafka_consumergroup_lag{group,topic,partition}
//	kafka_consumergroup_lag_sum{group,topic}
//	kafka_consumergroup_committed_offset{group,topic,partition}
//	kafka_consumergroup_members{group}
//	kafka_consumergroup_state{group,state}
//	kafka_consumergroup_partition_owner{group,topic,partition,member}
//	kafka_topic_partition_current_offset / _oldest_offset / _messages
//	kafka_topic_partition_leader / _replicas / _in_sync_replicas
//	kafka_topic_partition_under_replicated / _offline / _leader_is_preferred
//	kafka_cluster_brokers, kafka_cluster_controller_id
package main

import (
	"context"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/app"
	"github.com/nghuy8bit/kafka-lab/pkg/config"
	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
	"github.com/nghuy8bit/kafka-lab/pkg/logging"
	"github.com/nghuy8bit/kafka-lab/pkg/metrics"
)

const service = "lag-exporter"

func desc(name, help string, labels ...string) *prometheus.Desc {
	return prometheus.NewDesc(name, help, labels, nil)
}

var (
	dLag        = desc("kafka_consumergroup_lag", "High watermark - committed offset.", "group", "topic", "partition")
	dLagSum     = desc("kafka_consumergroup_lag_sum", "Sum of lag over partitions.", "group", "topic")
	dCommitted  = desc("kafka_consumergroup_committed_offset", "Committed offset (next record to read).", "group", "topic", "partition")
	dMembers    = desc("kafka_consumergroup_members", "Members in the group.", "group")
	dState      = desc("kafka_consumergroup_state", "1 for the current group state.", "group", "state")
	dOwner      = desc("kafka_consumergroup_partition_owner", "1 if member owns partition.", "group", "topic", "partition", "member")
	dEnd        = desc("kafka_topic_partition_current_offset", "Latest offset (high watermark).", "topic", "partition")
	dStart      = desc("kafka_topic_partition_oldest_offset", "Log start offset (oldest retained).", "topic", "partition")
	dMsgs       = desc("kafka_topic_partition_messages", "current - oldest offset (records retained, approx.).", "topic", "partition")
	dLeader     = desc("kafka_topic_partition_leader", "Broker id of the partition leader (-1 = offline).", "topic", "partition")
	dReplicas   = desc("kafka_topic_partition_replicas", "Replica count.", "topic", "partition")
	dISR        = desc("kafka_topic_partition_in_sync_replicas", "ISR size.", "topic", "partition")
	dURP        = desc("kafka_topic_partition_under_replicated", "1 if ISR < replicas.", "topic", "partition")
	dOffline    = desc("kafka_topic_partition_offline", "1 if the partition has no leader.", "topic", "partition")
	dPreferred  = desc("kafka_topic_partition_leader_is_preferred", "1 if leader == first replica.", "topic", "partition")
	dBrokers    = desc("kafka_cluster_brokers", "Brokers present in metadata.")
	dController = desc("kafka_cluster_controller_id", "Active controller id as seen by metadata.")
	dScrapeOK   = desc("kafka_lag_exporter_scrape_success", "1 if the last admin scrape succeeded.")
)

type snapshotCollector struct {
	mu   sync.RWMutex
	snap []prometheus.Metric
}

func (c *snapshotCollector) Describe(ch chan<- *prometheus.Desc) {
	for _, d := range []*prometheus.Desc{dLag, dLagSum, dCommitted, dMembers, dState, dOwner, dEnd, dStart, dMsgs,
		dLeader, dReplicas, dISR, dURP, dOffline, dPreferred, dBrokers, dController, dScrapeOK} {
		ch <- d
	}
}

func (c *snapshotCollector) Collect(ch chan<- prometheus.Metric) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	for _, m := range c.snap {
		ch <- m
	}
}

func main() {
	log := logging.New(service)
	ctx, stop := app.SignalContext()
	defer stop()

	cl, err := kgo.NewClient(kafka.BaseOpts(service, log)...)
	if err != nil {
		log.Error("client", "err", err)
		os.Exit(1)
	}
	adm := kadm.NewClient(cl)
	col := &snapshotCollector{}
	metrics.Registry.MustRegister(col)

	srv := metrics.NewServer(config.String("HTTP_ADDR", ":8080"))
	var lastOK time.Time
	var mu sync.Mutex
	srv.SetHealth(func() error {
		mu.Lock()
		defer mu.Unlock()
		if time.Since(lastOK) > time.Minute {
			return context.DeadlineExceeded
		}
		return nil
	})
	srv.Start(log)

	interval := config.Duration("SCRAPE_INTERVAL", 5*time.Second)
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		sctx, cancel := context.WithTimeout(ctx, interval*2)
		snap, err := scrape(sctx, adm)
		cancel()
		ok := 1.0
		if err != nil {
			ok = 0
			log.Warn("scrape failed", "err", err)
		} else {
			mu.Lock()
			lastOK = time.Now()
			mu.Unlock()
		}
		snap = append(snap, prometheus.MustNewConstMetric(dScrapeOK, prometheus.GaugeValue, ok))
		col.mu.Lock()
		col.snap = snap
		col.mu.Unlock()
		select {
		case <-ctx.Done():
			cl.Close()
			return
		case <-t.C:
		}
	}
}

func g(d *prometheus.Desc, v float64, labels ...string) prometheus.Metric {
	return prometheus.MustNewConstMetric(d, prometheus.GaugeValue, v, labels...)
}

func scrape(ctx context.Context, adm *kadm.Client) ([]prometheus.Metric, error) {
	var out []prometheus.Metric
	md, err := adm.Metadata(ctx)
	if err != nil {
		return out, err
	}
	out = append(out, g(dBrokers, float64(len(md.Brokers))), g(dController, float64(md.Controller)))

	var topics []string
	for _, td := range md.Topics.Sorted() {
		if strings.HasPrefix(td.Topic, "__") || strings.HasPrefix(td.Topic, "_") {
			continue
		}
		topics = append(topics, td.Topic)
		for _, pd := range td.Partitions.Sorted() {
			t, p := td.Topic, strconv.Itoa(int(pd.Partition))
			out = append(out,
				g(dLeader, float64(pd.Leader), t, p),
				g(dReplicas, float64(len(pd.Replicas)), t, p),
				g(dISR, float64(len(pd.ISR)), t, p),
				g(dURP, b2f(len(pd.ISR) < len(pd.Replicas)), t, p),
				g(dOffline, b2f(pd.Leader < 0), t, p),
				g(dPreferred, b2f(len(pd.Replicas) > 0 && pd.Leader == pd.Replicas[0]), t, p),
			)
		}
	}

	ends, err := adm.ListEndOffsets(ctx, topics...)
	if err == nil {
		starts, _ := adm.ListStartOffsets(ctx, topics...)
		ends.Each(func(o kadm.ListedOffset) {
			if o.Err != nil {
				return
			}
			t, p := o.Topic, strconv.Itoa(int(o.Partition))
			out = append(out, g(dEnd, float64(o.Offset), t, p))
			if s, ok := starts.Lookup(o.Topic, o.Partition); ok && s.Err == nil {
				out = append(out, g(dStart, float64(s.Offset), t, p), g(dMsgs, float64(o.Offset-s.Offset), t, p))
			}
		})
	}

	groups, err := adm.ListGroups(ctx)
	if err != nil {
		return out, nil
	}
	lags, err := adm.Lag(ctx, groups.Groups()...)
	if err != nil {
		return out, nil
	}
	for _, gl := range lags.Sorted() {
		group := gl.Group
		out = append(out, g(dMembers, float64(len(gl.Members)), group), g(dState, 1, group, gl.State))
		for topic, parts := range gl.Lag {
			var sum int64
			for part, l := range parts {
				p := strconv.Itoa(int(part))
				if l.Lag >= 0 {
					sum += l.Lag
					out = append(out, g(dLag, float64(l.Lag), group, topic, p))
				}
				if l.Commit.At >= 0 {
					out = append(out, g(dCommitted, float64(l.Commit.At), group, topic, p))
				}
				if l.Member != nil {
					out = append(out, g(dOwner, 1, group, topic, p, l.Member.ClientID))
				}
			}
			out = append(out, g(dLagSum, float64(sum), group, topic))
		}
	}
	return out, nil
}

func b2f(b bool) float64 {
	if b {
		return 1
	}
	return 0
}
