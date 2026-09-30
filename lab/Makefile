COMPOSE = docker compose
SERVICES = vehicle-service warranty-service inspection-service repair-service

.PHONY: up down build logs test seed demo clean ps lint chaos-up test-chaos docs-render docs-check
up:
	$(COMPOSE) up --build -d --wait
down:
	$(COMPOSE) down
build:
	$(COMPOSE) --profile tools build
logs:
	$(COMPOSE) logs -f --tail=100
ps:
	$(COMPOSE) ps
test:
	@set -e; for service in $(SERVICES); do $(COMPOSE) exec -T $$service pytest -q tests; done
	$(COMPOSE) run --build --rm toolbox pytest -q tests
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
