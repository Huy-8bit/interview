package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/kmsg"
)

func init() {
	register("topics", "describe topics: partition leader / replicas / ISR (+ under-replicated flags)", cmdTopics)
	register("brokers", "list brokers and the active KRaft controller", cmdBrokers)
	register("stats", "records per partition with skew summary (-snapshot/-since for deltas)", cmdStats)
	register("hash", "show murmur2(key) -> partition mapping used by the default partitioner", cmdHash)
}

func cmdTopics(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("topics", flag.ExitOnError)
	topic := fs.String("topic", "", "only this topic (comma separated list allowed)")
	internal := fs.Bool("internal", false, "include internal topics (__consumer_offsets, ...)")
	_ = fs.Parse(args)

	adm, cl, err := newAdmin()
	if err != nil {
		return err
	}
	defer cl.Close()
	ctx, cancel := withTimeout(ctx, 15*time.Second)
	defer cancel()
	var topics []string
	if *topic != "" {
		topics = strings.Split(*topic, ",")
	}
	md, err := adm.Metadata(ctx, topics...)
	if err != nil {
		return err
	}
	brokers := map[int32]string{}
	for _, b := range md.Brokers {
		brokers[b.NodeID] = fmt.Sprintf("kafka-%d", b.NodeID)
	}
	name := func(id int32) string {
		if n, ok := brokers[id]; ok {
			return n
		}
		return fmt.Sprintf("broker-%d(DOWN)", id)
	}
	names := func(ids []int32) string {
		s := make([]string, len(ids))
		for i, id := range ids {
			s[i] = name(id)
		}
		return strings.Join(s, ",")
	}

	fmt.Printf("brokers alive in metadata: %d\n\n", len(md.Brokers))
	w := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	fmt.Fprintln(w, "TOPIC\tPART\tLEADER\tREPLICAS\tISR\tEPOCH\tSTATUS")
	leaders := map[int32]int{}
	for _, td := range md.Topics.Sorted() {
		if td.IsInternal && !*internal || (strings.HasPrefix(td.Topic, "_") && !*internal) {
			continue
		}
		if td.Err != nil {
			fmt.Fprintf(w, "%s\t-\t-\t-\t-\t-\t%v\n", td.Topic, td.Err)
			continue
		}
		for _, p := range td.Partitions.Sorted() {
			status := "OK"
			switch {
			case p.Leader < 0:
				status = "OFFLINE (no leader)"
			case len(p.ISR) < len(p.Replicas):
				status = fmt.Sprintf("UNDER-REPLICATED (%d/%d in sync)", len(p.ISR), len(p.Replicas))
			}
			if p.Leader >= 0 && len(p.Replicas) > 0 && p.Leader != p.Replicas[0] {
				status += "  leader!=preferred"
			}
			leader := "none"
			if p.Leader >= 0 {
				leader = name(p.Leader)
				leaders[p.Leader]++
			}
			fmt.Fprintf(w, "%s\t%d\t%s\t%s\t%s\t%d\t%s\n", td.Topic, p.Partition, leader, names(p.Replicas), names(p.ISR), p.LeaderEpoch, status)
		}
	}
	_ = w.Flush()
	ids := make([]int32, 0, len(leaders))
	for id := range leaders {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	fmt.Print("\nleaders per broker:")
	for _, id := range ids {
		fmt.Printf("  %s=%d", name(id), leaders[id])
	}
	fmt.Println()
	return nil
}

func cmdBrokers(ctx context.Context, args []string) error {
	adm, cl, err := newAdmin()
	if err != nil {
		return err
	}
	defer cl.Close()
	ctx, cancel := withTimeout(ctx, 10*time.Second)
	defer cancel()
	md, err := adm.BrokerMetadata(ctx)
	if err != nil {
		return err
	}
	fmt.Printf("cluster id: %s\n", md.Cluster)
	fmt.Printf("metadata 'controller id': %d  (in KRaft this is just a broker that forwards admin requests, NOT the quorum leader)\n\n", md.Controller)
	w := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	fmt.Fprintln(w, "NODE\tADVERTISED ENDPOINT (for this client's listener)\tRACK")
	for _, b := range md.Brokers {
		rack := "-"
		if b.Rack != nil {
			rack = *b.Rack
		}
		fmt.Fprintf(w, "%d\t%s:%d\t%s\n", b.NodeID, b.Host, b.Port, rack)
	}
	if err := w.Flush(); err != nil {
		return err
	}

	// The real KRaft controller = leader of the __cluster_metadata Raft log.
	req := kmsg.NewPtrDescribeQuorumRequest()
	rt := kmsg.NewDescribeQuorumRequestTopic()
	rt.Topic = "__cluster_metadata"
	rp := kmsg.NewDescribeQuorumRequestTopicPartition()
	rp.Partition = 0
	rt.Partitions = append(rt.Partitions, rp)
	req.Topics = append(req.Topics, rt)
	resp, err := req.RequestWith(ctx, cl)
	if err != nil {
		return fmt.Errorf("describe quorum: %w", err)
	}
	for _, t := range resp.Topics {
		for _, p := range t.Partitions {
			fmt.Printf("\nKRaft metadata quorum (%s): ACTIVE CONTROLLER = node %d, leader epoch %d, high watermark %d\n",
				t.Topic, p.LeaderID, p.LeaderEpoch, p.HighWatermark)
			w := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
			fmt.Fprintln(w, "VOTER\tROLE\tLOG END OFFSET\tLAG")
			for _, v := range p.CurrentVoters {
				role := "follower"
				if v.ReplicaID == p.LeaderID {
					role = "LEADER"
				}
				fmt.Fprintf(w, "%d\t%s\t%d\t%d\n", v.ReplicaID, role, v.LogEndOffset, p.HighWatermark-v.LogEndOffset)
			}
			_ = w.Flush()
		}
	}
	return nil
}

type offsetsSnapshot map[string]map[int32]int64

func cmdStats(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("stats", flag.ExitOnError)
	topic := fs.String("topic", "orders", "topic")
	snapshot := fs.String("snapshot", "", "write current end offsets to this file and exit")
	since := fs.String("since", "", "show records produced since this snapshot file")
	asJSON := fs.Bool("json", false, "JSON output")
	_ = fs.Parse(args)

	adm, cl, err := newAdmin()
	if err != nil {
		return err
	}
	defer cl.Close()
	ctx, cancel := withTimeout(ctx, 15*time.Second)
	defer cancel()
	ends, err := adm.ListEndOffsets(ctx, *topic)
	if err != nil {
		return err
	}
	if err := ends.Error(); err != nil {
		return err
	}
	if *snapshot != "" {
		snap := offsetsSnapshot{*topic: {}}
		ends.Each(func(o kadm.ListedOffset) { snap[*topic][o.Partition] = o.Offset })
		b, _ := json.Marshal(snap)
		return os.WriteFile(*snapshot, b, 0o644)
	}
	base := map[int32]int64{}
	label := "records retained (end - start offset)"
	if *since != "" {
		b, err := os.ReadFile(*since)
		if err != nil {
			return err
		}
		var snap offsetsSnapshot
		if err := json.Unmarshal(b, &snap); err != nil {
			return err
		}
		base = snap[*topic]
		label = "records produced since snapshot"
	} else {
		starts, err := adm.ListStartOffsets(ctx, *topic)
		if err != nil {
			return err
		}
		starts.Each(func(o kadm.ListedOffset) { base[o.Partition] = o.Offset })
	}
	type row struct {
		Partition int32 `json:"partition"`
		Records   int64 `json:"records"`
	}
	var rows []row
	ends.Each(func(o kadm.ListedOffset) { rows = append(rows, row{o.Partition, o.Offset - base[o.Partition]}) })
	sort.Slice(rows, func(i, j int) bool { return rows[i].Partition < rows[j].Partition })
	if len(rows) == 0 {
		return errors.New("no partitions")
	}
	var total, maxV int64
	minV := int64(math.MaxInt64)
	for _, r := range rows {
		total += r.Records
		maxV = max(maxV, r.Records)
		minV = min(minV, r.Records)
	}
	avg := float64(total) / float64(len(rows))
	var variance float64
	for _, r := range rows {
		variance += (float64(r.Records) - avg) * (float64(r.Records) - avg)
	}
	stddev := math.Sqrt(variance / float64(len(rows)))
	skew := 0.0
	if avg > 0 {
		skew = float64(maxV) / avg
	}
	if *asJSON {
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"topic": *topic, "partitions": rows, "total": total,
			"max_over_avg": skew, "stddev": stddev})
	}
	fmt.Printf("topic=%s  %s\n\n", *topic, label)
	for _, r := range rows {
		bar := 0
		if maxV > 0 {
			bar = int(float64(r.Records) / float64(maxV) * 50)
		}
		pct := 0.0
		if total > 0 {
			pct = float64(r.Records) / float64(total) * 100
		}
		fmt.Printf("  P%-3d %10d  %5.1f%%  %s\n", r.Partition, r.Records, pct, strings.Repeat("#", bar))
	}
	fmt.Printf("\n  total=%d  avg=%.0f  min=%d  max=%d  stddev=%.0f  max/avg=%.2f", total, avg, minV, maxV, stddev, skew)
	if skew >= 2 {
		fmt.Printf("  <-- HOT PARTITION (one partition gets %.1fx its fair share)", skew)
	}
	fmt.Println()
	return nil
}

// murmur2 is Kafka's hash (org.apache.kafka.common.utils.Utils.murmur2).
func murmur2(data []byte) int32 {
	const (
		seed uint32 = 0x9747b28c
		m    uint32 = 0x5bd1e995
		r           = 24
	)
	length := len(data)
	h := seed ^ uint32(length)
	for i := 0; i+4 <= length; i += 4 {
		k := uint32(data[i]) | uint32(data[i+1])<<8 | uint32(data[i+2])<<16 | uint32(data[i+3])<<24
		k *= m
		k ^= k >> r
		k *= m
		h *= m
		h ^= k
	}
	tail := length &^ 3
	switch length % 4 {
	case 3:
		h ^= uint32(data[tail+2]) << 16
		fallthrough
	case 2:
		h ^= uint32(data[tail+1]) << 8
		fallthrough
	case 1:
		h ^= uint32(data[tail])
		h *= m
	}
	h ^= h >> 13
	h *= m
	h ^= h >> 15
	return int32(h)
}

func cmdHash(_ context.Context, args []string) error {
	fs := flag.NewFlagSet("hash", flag.ExitOnError)
	n := fs.Int("partitions", 6, "partition count")
	_ = fs.Parse(args)
	keys := fs.Args()
	if len(keys) == 0 {
		keys = []string{"order-100", "order-101", "order-102", "user-1001", "user-1002", "order-HOT"}
	}
	part := kgo.StickyKeyPartitioner(nil).ForTopic("x")
	w := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	fmt.Fprintf(w, "KEY\tmurmur2(key)\t& 0x7fffffff\t%% %d = PARTITION\tfranz-go partitioner\n", *n)
	for _, k := range keys {
		h := murmur2([]byte(k))
		pos := h & 0x7fffffff
		fmt.Fprintf(w, "%s\t%d\t%d\tP%d\tP%d\n", k, h, pos, pos%int32(*n), part.Partition(&kgo.Record{Key: []byte(k)}, *n))
	}
	return w.Flush()
}
