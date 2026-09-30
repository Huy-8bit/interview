COMPOSE = docker compose
SERVICES = vehicle-service warranty-service inspection-service repair-service

.PHONY: up down build logs test seed demo clean ps lint chaos-up test-chaos docs-render docs-check cluster-check cluster-test
up:
	bash scripts/up.sh
down:
	$(COMPOSE) down
build:
	$(COMPOSE) --profile tools build
logs:
	$(COMPOSE) logs -f --tail=100
ps:
	$(COMPOSE) ps
test:
	sh scripts/run_tests.sh
lint:
	$(COMPOSE) run --build --rm --no-deps toolbox ruff check /opt/common /opt/lab
	@set -e; for service in $(SERVICES); do $(COMPOSE) exec -T $$service ruff check app tests; done
demo:
	$(COMPOSE) run --build --rm toolbox python scripts/demo.py
seed:
	$(COMPOSE) run --build --rm toolbox python scripts/seed.py --count 100
chaos-up:
	$(COMPOSE) -f docker-compose.yml -f compose.chaos.yml up -d --build --wait
test-chaos:
	$(COMPOSE) run --build --rm --no-deps toolbox python scripts/chaos_verify.py
clean:
	$(COMPOSE) --profile tools down -v --remove-orphans
docs-render:
	sh scripts/render_docs.sh
docs-check:
	docker run --rm --network none -v "$(CURDIR):/work:ro" -w /work python:3.12-slim python scripts/docs.py check
cluster-check:
	$(COMPOSE) run --build --rm --no-deps toolbox python scripts/cluster_verify.py verify
cluster-test:
	sh scripts/cluster_drills.sh

.PHONY: db-check cdc-demo db-test
db-check:
	$(COMPOSE) run --build --rm --no-deps toolbox python scripts/postgres_cdc_verify.py verify
cdc-demo:
	mkdir -p artifacts/postgres-cdc/demo
	$(COMPOSE) run --build --rm --no-deps --user "$$(id -u):$$(id -g)" -v "$(CURDIR)/artifacts/postgres-cdc/demo:/evidence" toolbox python scripts/postgres_cdc_verify.py cdc --output /evidence/insert-update-delete.json
db-test:
	sh scripts/postgres_cdc_drills.sh

.PHONY: traffic-start traffic-stop traffic-logs traffic-status traffic-rate traffic-scenario
traffic-start:
	$(COMPOSE) up -d --build --no-deps traffic-generator
traffic-stop:
	$(COMPOSE) stop traffic-generator
traffic-logs:
	$(COMPOSE) logs -f --tail=30 traffic-generator
traffic-status:
	$(COMPOSE) exec -T traffic-generator cat /tmp/traffic-generator-status.json
# make traffic-rate RPS=50 | RPS=0 USERS=10 | INTERVAL_MS=500; no variables prints the current rate
traffic-rate:
	$(COMPOSE) exec -T traffic-generator python -m traffic_generator.control $(if $(RPS),--rps $(RPS)) $(if $(USERS),--virtual-users $(USERS)) $(if $(INTERVAL_MS),--interval-ms $(INTERVAL_MS))
traffic-scenario:
	$(COMPOSE) run --build --rm --no-deps -e TRAFFIC_MODE=scenario traffic-generator

.PHONY: traffic-test traffic-drills
traffic-test:
	sh scripts/traffic_scenarios.sh
traffic-drills:
	sh scripts/traffic_drills.sh

.PHONY: monitoring-check lag-demo
monitoring-check:
	mkdir -p artifacts/observability
	$(COMPOSE) run --build --rm --no-deps --user "$$(id -u):$$(id -g)" -v "$(CURDIR)/artifacts/observability:/evidence" toolbox python scripts/monitoring_verify.py --output /evidence/monitoring.json
lag-demo:
	bash scripts/lag_demo.sh

.PHONY: cdc-projection-check
cdc-projection-check:
	mkdir -p artifacts/observability
	$(COMPOSE) run --build --rm --no-deps --user "$$(id -u):$$(id -g)" -v "$(CURDIR)/artifacts/observability:/evidence" toolbox python scripts/cdc_projection_verify.py --output /evidence/cdc-projection.json

.PHONY: rabbitmq-status report-dlq report-replay report-drill workers-scale task-backlog-demo rabbitmq-drills
# Cluster nodes, quorum queue leader/members/online, ready/unacked/consumers
rabbitmq-status:
	$(COMPOSE) exec -T inspection-service python -m app.reports.cli status
# Dead-lettered report tasks with the failure recorded in inspection_db
report-dlq:
	$(COMPOSE) exec -T inspection-service python -m app.reports.cli dlq
report-replay:
	$(COMPOSE) exec -T inspection-service python -m app.reports.cli replay --limit $(or $(LIMIT),10)
# make report-drill FAULT=transient|hang|stuck ; no FAULT = invalid input (permanent)
report-drill:
	$(COMPOSE) exec -T inspection-service python -m app.reports.cli submit $(if $(FAULT),--fault $(FAULT))
# make workers-scale N=4
workers-scale:
	$(COMPOSE) up -d --no-deps --wait --scale report-worker=$(or $(N),2) report-worker
task-backlog-demo:
	bash scripts/task_backlog_demo.sh
rabbitmq-drills:
	bash scripts/rabbitmq_drills.sh
