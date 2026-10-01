package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/twmb/franz-go/pkg/kadm"
)

func init() {
	register("group", "consumer group members, assignment, committed offset and lag (-watch, -wait-members)", cmdGroup)
	register("groups", "list consumer groups with state and total lag", cmdGroups)
}

type memberView struct {
	clientID, host, kind string
	parts                map[string][]int32
}

type groupView struct {
	name, state, protocol, kind string
	members                     []memberView
}

// describeGroup works for both the classic protocol (JoinGroup/SyncGroup) and
// the KIP-848 "consumer" protocol (ConsumerGroupHeartbeat).
func describeGroup(ctx context.Context, adm *kadm.Client, group string) (groupView, error) {
	gv := groupView{name: group}
	dg, err := adm.DescribeGroups(ctx, group)
	if err == nil {
		if d, ok := dg[group]; ok && d.Err == nil && d.State != "Dead" {
			gv.state, gv.protocol, gv.kind = d.State, d.Protocol, "classic"
			for _, m := range d.Members {
				mv := memberView{clientID: m.ClientID, host: m.ClientHost, kind: "classic", parts: map[string][]int32{}}
				if c, ok := m.Assigned.AsConsumer(); ok {
					for _, t := range c.Topics {
						mv.parts[t.Topic] = append(mv.parts[t.Topic], t.Partitions...)
					}
				}
				gv.members = append(gv.members, mv)
			}
			return gv, nil
		}
	}
	cg, err := adm.DescribeConsumerGroups(ctx, group)
	if err != nil {
		return gv, err
	}
	d, ok := cg[group]
	if !ok || d.Err != nil {
		return gv, fmt.Errorf("group %s not found: %v", group, d.Err)
	}
	gv.state, gv.protocol, gv.kind = d.State, d.AssignorName, "consumer (KIP-848)"
	for _, m := range d.Members {
		mv := memberView{clientID: m.ClientID, host: m.ClientHost, kind: "consumer", parts: map[string][]int32{}}
		for t, ps := range m.Assignment {
			for p := range ps {
				mv.parts[t] = append(mv.parts[t], p)
			}
		}
		gv.members = append(gv.members, mv)
	}
	return gv, nil
}

type lagRow struct {
	topic             string
	partition         int32
	committed, end    int64
	lag               int64
	owner             string
	hasCommit, hasEnd bool
}

func groupLag(ctx context.Context, adm *kadm.Client, group string, owners map[string]string) ([]lagRow, error) {
	offs, err := adm.FetchOffsets(ctx, group)
	if err != nil {
		return nil, err
	}
	topicsSet := map[string]bool{}
	offs.Each(func(o kadm.OffsetResponse) { topicsSet[o.Topic] = true })
	for k := range owners {
		topicsSet[strings.SplitN(k, "/", 2)[0]] = true
	}
	var topics []string
	for t := range topicsSet {
		topics = append(topics, t)
	}
	if len(topics) == 0 {
		return nil, nil
	}
	ends, err := adm.ListEndOffsets(ctx, topics...)
	if err != nil {
		return nil, err
	}
	var rows []lagRow
	ends.Each(func(e kadm.ListedOffset) {
		r := lagRow{topic: e.Topic, partition: e.Partition, end: e.Offset, hasEnd: e.Err == nil, lag: -1}
		if c, ok := offs.Lookup(e.Topic, e.Partition); ok && c.Err == nil && c.At >= 0 {
			r.committed, r.hasCommit = c.At, true
			r.lag = e.Offset - c.At
		}
		r.owner = owners[fmt.Sprintf("%s/%d", e.Topic, e.Partition)]
		rows = append(rows, r)
	})
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].topic != rows[j].topic {
			return rows[i].topic < rows[j].topic
		}
		return rows[i].partition < rows[j].partition
	})
	return rows, nil
}

func printGroup(ctx context.Context, adm *kadm.Client, group string) (groupView, error) {
	gv, err := describeGroup(ctx, adm, group)
	if err != nil {
		return gv, err
	}
	fmt.Printf("[%s] group=%s state=%s protocol=%s assignor=%s members=%d\n",
		time.Now().Format("15:04:05"), gv.name, gv.state, gv.kind, gv.protocol, len(gv.members))
	owners := map[string]string{}
	sort.Slice(gv.members, func(i, j int) bool { return gv.members[i].clientID < gv.members[j].clientID })
	w := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	fmt.Fprintln(w, "  MEMBER (client.id)\tHOST\tASSIGNED PARTITIONS")
	for _, m := range gv.members {
		var parts []string
		topics := make([]string, 0, len(m.parts))
		for t := range m.parts {
			topics = append(topics, t)
		}
		sort.Strings(topics)
		for _, t := range topics {
			ps := m.parts[t]
			sort.Slice(ps, func(i, j int) bool { return ps[i] < ps[j] })
			var s []string
			for _, p := range ps {
				s = append(s, fmt.Sprintf("P%d", p))
				owners[fmt.Sprintf("%s/%d", t, p)] = m.clientID
			}
			parts = append(parts, fmt.Sprintf("%s[%s]", t, strings.Join(s, " ")))
		}
		asg := strings.Join(parts, " ")
		if asg == "" {
			asg = "(none) <-- IDLE member"
		}
		fmt.Fprintf(w, "  %s\t%s\t%s\n", m.clientID, m.host, asg)
	}
	_ = w.Flush()
	rows, err := groupLag(ctx, adm, group, owners)
	if err != nil {
		return gv, err
	}
	w = tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	fmt.Fprintln(w, "  TOPIC\tPART\tCOMMITTED\tLOG-END(HW)\tLAG\tOWNER")
	var total int64
	for _, r := range rows {
		c, l := "-", "-"
		if r.hasCommit {
			c = fmt.Sprint(r.committed)
			l = fmt.Sprint(r.lag)
			total += r.lag
		}
		owner := r.owner
		if owner == "" {
			owner = "-"
		}
		fmt.Fprintf(w, "  %s\t%d\t%s\t%d\t%s\t%s\n", r.topic, r.partition, c, r.end, l, owner)
	}
	_ = w.Flush()
	fmt.Printf("  total lag: %d\n", total)
	return gv, nil
}

func cmdGroup(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("group", flag.ExitOnError)
	group := fs.String("group", "order-processing-group", "consumer group")
	watch := fs.Duration("watch", 0, "repeat every interval (Ctrl-C to stop)")
	waitMembers := fs.Int("wait-members", 0, "wait until the group is Stable with N members, print, exit")
	timeout := fs.Duration("timeout", 90*time.Second, "timeout for -wait-members")
	_ = fs.Parse(args)
	adm, cl, err := newAdmin()
	if err != nil {
		return err
	}
	defer cl.Close()

	if *waitMembers > 0 {
		deadline := time.Now().Add(*timeout)
		for time.Now().Before(deadline) {
			c, cancel := withTimeout(ctx, 10*time.Second)
			gv, err := describeGroup(c, adm, *group)
			cancel()
			if err == nil && gv.state == "Stable" && len(gv.members) == *waitMembers {
				c, cancel := withTimeout(ctx, 10*time.Second)
				_, err := printGroup(c, adm, *group)
				cancel()
				return err
			}
			time.Sleep(time.Second)
		}
		return fmt.Errorf("group %s did not become Stable with %d members within %s", *group, *waitMembers, *timeout)
	}
	for {
		c, cancel := withTimeout(ctx, 10*time.Second)
		_, err := printGroup(c, adm, *group)
		cancel()
		if err != nil {
			fmt.Println("  error:", err)
		}
		if *watch <= 0 {
			return nil
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(*watch):
		}
		fmt.Println()
	}
}

func cmdGroups(ctx context.Context, args []string) error {
	adm, cl, err := newAdmin()
	if err != nil {
		return err
	}
	defer cl.Close()
	ctx, cancel := withTimeout(ctx, 15*time.Second)
	defer cancel()
	lg, err := adm.ListGroups(ctx)
	if err != nil {
		return err
	}
	names := lg.Groups()
	sort.Strings(names)
	w := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	fmt.Fprintln(w, "GROUP\tSTATE\tPROTOCOL\tMEMBERS\tTOTAL LAG")
	for _, g := range names {
		gv, err := describeGroup(ctx, adm, g)
		if err != nil {
			fmt.Fprintf(w, "%s\t?\t?\t?\t%v\n", g, err)
			continue
		}
		rows, _ := groupLag(ctx, adm, g, nil)
		var total int64
		for _, r := range rows {
			if r.hasCommit {
				total += r.lag
			}
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%d\t%d\n", g, gv.state, gv.kind, len(gv.members), total)
	}
	return w.Flush()
}
