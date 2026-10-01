# Kafka Learning Lab — `make help` lists everything.
SHELL := /bin/bash
.DEFAULT_GOAL := help
DC := docker compose

## ---------- lifecycle ----------
up: ## build + start the whole lab (docker compose up -d --build)
	@test -f .env || cp .env.example .env
	$(DC) up -d --build
	@echo "Kafka UI http://localhost:8080 | Grafana http://localhost:3000 (admin/admin) | Prometheus http://localhost:9090"

down: ## stop and remove containers (keeps data volumes)
	$(DC) --profile scale down

clean: ## stop and DELETE all data volumes
	$(DC) --profile scale down -v --remove-orphans

ps: ## container status
	$(DC) ps -a --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'

status: ## full health verification (brokers, quorum, topics, ISR, groups, UIs)
	@./scripts/cluster-health.sh

health: status

logs: ## follow logs of the Go services (S=service to filter)
	$(DC) logs -f --tail=50 $(or $(S),producer-service order-consumer-1 order-consumer-2 order-consumer-3 payment-consumer notification-consumer)

logs-kafka: ## follow broker logs
	$(DC) logs -f --tail=50 kafka-1 kafka-2 kafka-3

## ---------- topics / data ----------
topics: ## partition leader / replicas / ISR table
	@./scripts/describe-topics.sh $(T)

create-topics: ## (re)apply kafka/topics/topics.conf
	@./scripts/create-topics.sh

produce: ## send one OrderCreated through producer-service
	@./scripts/produce-test-message.sh

consume: ## print the first 10 records of T (default orders)
	@./scripts/consume-test-message.sh $(or $(T),orders) 10

consumers: ## consumer groups: members, assignment, lag
	@./scripts/describe-consumer-groups.sh $(G)

lag: ## total lag per group (G=group for per-partition detail)
	@./scripts/consumer-lag.sh $(G)

stats: ## records per partition of T (default orders)
	@./scripts/partition-stats.sh $(or $(T),orders)

## ---------- failures ----------
stop-broker-1: ## graceful stop of kafka-1
	@./scripts/stop-broker.sh 1
start-broker-1: ## start kafka-1 and wait for ISR catch-up
	@./scripts/start-broker.sh 1
stop-broker-2:
	@./scripts/stop-broker.sh 2
start-broker-2:
	@./scripts/start-broker.sh 2
stop-broker-3:
	@./scripts/stop-broker.sh 3
start-broker-3:
	@./scripts/start-broker.sh 3

## ---------- traffic ----------
traffic-status: ## traffic generator status
	@./scripts/traffic.sh status
traffic-stop: ## stop background traffic
	@./scripts/traffic.sh stop
traffic-default: ## background traffic 5 msg/s
	@./scripts/traffic.sh default
traffic-burst: ## 10k msg/s bursts for 10s every 30s during 2 minutes
	@./scripts/traffic.sh burst 100 120s 10000 10s
traffic-skewed: ## 80% of records with the same key during 60s
	@./scripts/traffic.sh skewed 2000 60s 0.8

## ---------- labs ----------
reset: ## soft reset after a lab (topics configs, faults, groups, redis, traffic)
	@./scripts/reset-lab.sh
reset-hard: ## wipe everything and start from scratch
	@./scripts/reset-lab.sh --hard

lab: ## run a lab: make lab L=04_ordering
	@test -n "$(L)" || (echo "usage: make lab L=<folder under labs/>, e.g. L=04_ordering" && ls labs && exit 1)
	@bash labs/$(L)/run.sh

labs-list: ## list labs
	@find labs -name run.sh | sort | sed 's|/run.sh||'

dashboards: ## regenerate Grafana dashboards from monitoring/grafana/dashgen.py
	python3 monitoring/grafana/dashgen.py

test: ## go vet + unit tests
	go vet ./... && go test ./...

help:
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: up down clean ps status health logs logs-kafka topics create-topics produce consume consumers lag stats \
	stop-broker-1 start-broker-1 stop-broker-2 start-broker-2 stop-broker-3 start-broker-3 \
	traffic-status traffic-stop traffic-default traffic-burst traffic-skewed reset reset-hard lab labs-list dashboards test help
