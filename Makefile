.PHONY: build up down shell rebuild test test-quick test-e2e logs

build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down

shell:
	docker compose exec opencode-pai bash

rebuild: down
	docker compose build --no-cache
	docker compose up -d

test:
	@echo "Running full test suite..."
	docker compose exec opencode-pai bash -c "cd /workspace && bun test"

test-quick:
	@echo "Running quick validation tests..."
	docker compose exec opencode-pai bash -c "node --version && bun --version && python3 --version && opencode --version && gh --version"

test-e2e:
	@echo "Running end-to-end tests..."
	docker compose exec opencode-pai bash -c "cd /workspace && bun test --filter e2e"

logs:
	docker compose logs -f
