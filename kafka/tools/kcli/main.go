// kcli — the lab's Kafka CLI (Go + franz-go). Runs inside the `toolbox`
// container (scripts call `docker compose exec toolbox kcli ...`) or on the host
// with KAFKA_BROKERS=localhost:9092,localhost:9093,localhost:9094.
//
//	kcli topics      [-topic t]                    leader / replicas / ISR per partition
//	kcli brokers                                   brokers + active controller
//	kcli stats       -topic t [-snapshot f|-since f]  records per partition (+ skew)
//	kcli hash        -partitions 6 key...          murmur2(key) -> partition
//	kcli produce     -topic t -key k -value v      produce raw records
//	kcli order       -topic orders [-fault f]      produce one OrderCreated JSON event
//	kcli consume     -topic t [-group g]           print records (partition/offset/key/headers)
//	kcli group       -group g [-watch 2s]          members, assignment, committed offsets, lag
//	kcli ordering-test                             proves per-partition ordering
//	kcli bench-produce / bench-consume             performance labs
//	kcli idempotence-test                          duplicates with/without idempotent producer
//	kcli dlq-inspect / dlq-replay                  dead letter queue tooling
//	kcli large-message                             max.message.bytes + chunking
//	kcli sr-produce                                Schema Registry wire format producer
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/nghuy8bit/kafka-lab/pkg/config"
	"github.com/nghuy8bit/kafka-lab/pkg/kafka"
)

type command struct {
	name string
	help string
	run  func(ctx context.Context, args []string) error
}

var commands []command

func register(name, help string, run func(ctx context.Context, args []string) error) {
	commands = append(commands, command{name, help, run})
}

var log = slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn}))

func main() {
	if len(os.Args) < 2 || os.Args[1] == "-h" || os.Args[1] == "help" {
		usage()
		os.Exit(0)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	name := os.Args[1]
	for _, c := range commands {
		if c.name == name {
			if err := c.run(ctx, os.Args[2:]); err != nil {
				fmt.Fprintln(os.Stderr, "ERROR:", err)
				os.Exit(1)
			}
			return
		}
	}
	fmt.Fprintf(os.Stderr, "unknown command %q\n\n", name)
	usage()
	os.Exit(2)
}

func usage() {
	sort.Slice(commands, func(i, j int) bool { return commands[i].name < commands[j].name })
	fmt.Println("kcli — Kafka lab CLI. Brokers:", strings.Join(config.Brokers(), ","))
	fmt.Println()
	for _, c := range commands {
		fmt.Printf("  %-18s %s\n", c.name, c.help)
	}
	fmt.Println("\nRun `kcli <command> -h` for flags.")
}

func init() {
	register("version", "print version (used by the toolbox healthcheck)", func(context.Context, []string) error {
		fmt.Println("kcli 1.0 (franz-go)")
		return nil
	})
}

func newClient(extra ...kgo.Opt) (*kgo.Client, error) {
	opts := append(kafka.BaseOpts("kcli", log), extra...)
	return kgo.NewClient(opts...)
}

func newAdmin() (*kadm.Client, *kgo.Client, error) {
	cl, err := newClient()
	if err != nil {
		return nil, nil, err
	}
	return kadm.NewClient(cl), cl, nil
}

func withTimeout(ctx context.Context, d time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, d)
}

func joinInt32(xs []int32) string {
	s := make([]string, len(xs))
	for i, x := range xs {
		s[i] = fmt.Sprint(x)
	}
	return strings.Join(s, ",")
}
