.PHONY: build up down shell rebuild test test-quick test-e2e test-all test-tmux logs

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

test-quick:
	docker compose exec opencode-pai bash -c '\
		bash tests/connectivity.sh && \
		bash tests/agent-defs.sh && \
		bash tests/tool-access.sh'

test-e2e:
	docker compose exec opencode-pai bash -c '\
		bash tests/model-routing.sh && \
		bash tests/e2e-smoke.sh'

test: test-quick test-e2e

test-all:
	docker compose exec opencode-pai bash -c '\
		bash tests/connectivity.sh && \
		bash tests/agent-defs.sh && \
		bash tests/tool-access.sh && \
		bash tests/model-routing.sh && \
		bash tests/e2e-smoke.sh'

test-tmux:
	docker compose exec opencode-pai bash -c '\
		if command -v tmux &>/dev/null; then \
			tmux new-session -d -s tests "bash tests/connectivity.sh && bash tests/agent-defs.sh && bash tests/tool-access.sh && bash tests/model-routing.sh && bash tests/e2e-smoke.sh; read" && \
			tmux attach -t tests; \
		else \
			echo "tmux not available, running inline"; \
			bash tests/connectivity.sh && bash tests/agent-defs.sh && bash tests/tool-access.sh && bash tests/model-routing.sh && bash tests/e2e-smoke.sh; \
		fi'

logs:
	docker compose logs -f
