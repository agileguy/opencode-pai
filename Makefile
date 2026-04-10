.PHONY: build up down shell rebuild test test-quick test-e2e test-all test-tmux logs \
       eval-engineer eval-boss eval-architect eval-all \
       research-engineer research-boss research-architect research-all research-stop research-status

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
		bash /workspace/repos/opencode-pai/tests/connectivity.sh && \
		bash /workspace/repos/opencode-pai/tests/agent-defs.sh && \
		bash /workspace/repos/opencode-pai/tests/tool-access.sh && \
		bash /workspace/repos/opencode-pai/tests/skill-loading.sh && \
		bash /workspace/repos/opencode-pai/tests/plugin-hooks.sh'

test-e2e:
	docker compose exec opencode-pai bash -c '\
		bash /workspace/repos/opencode-pai/tests/model-routing.sh && \
		bash /workspace/repos/opencode-pai/tests/e2e-smoke.sh && \
		bash /workspace/repos/opencode-pai/tests/e2e-algorithm.sh && \
		bash /workspace/repos/opencode-pai/tests/e2e-algorithm-auto.sh'

test: test-quick test-e2e

test-all:
	docker compose exec opencode-pai bash -c '\
		bash /workspace/repos/opencode-pai/tests/connectivity.sh && \
		bash /workspace/repos/opencode-pai/tests/agent-defs.sh && \
		bash /workspace/repos/opencode-pai/tests/tool-access.sh && \
		bash /workspace/repos/opencode-pai/tests/model-routing.sh && \
		bash /workspace/repos/opencode-pai/tests/e2e-smoke.sh'

test-tmux:
	docker compose exec opencode-pai bash -c '\
		if command -v tmux &>/dev/null; then \
			tmux new-session -d -s tests "bash /workspace/repos/opencode-pai/tests/connectivity.sh && bash /workspace/repos/opencode-pai/tests/agent-defs.sh && bash /workspace/repos/opencode-pai/tests/tool-access.sh && bash /workspace/repos/opencode-pai/tests/model-routing.sh && bash /workspace/repos/opencode-pai/tests/e2e-smoke.sh; read" && \
			tmux attach -t tests; \
		else \
			echo "tmux not available, running inline"; \
			bash /workspace/repos/opencode-pai/tests/connectivity.sh && bash /workspace/repos/opencode-pai/tests/agent-defs.sh && bash /workspace/repos/opencode-pai/tests/tool-access.sh && bash /workspace/repos/opencode-pai/tests/model-routing.sh && bash /workspace/repos/opencode-pai/tests/e2e-smoke.sh; \
		fi'

logs:
	docker compose logs -f

# ─── Eval: Run baseline evaluations ───────────────────────────

eval-engineer:
	docker compose exec opencode-pai bash -c \
		'cd /workspace/repos/opencode-pai && bash eval/run-eval.sh pai-engineer'

eval-boss:
	docker compose exec opencode-pai bash -c \
		'cd /workspace/repos/opencode-pai && bash eval/run-eval.sh pai-boss'

eval-architect:
	docker compose exec opencode-pai bash -c \
		'cd /workspace/repos/opencode-pai && bash eval/run-eval.sh pai-architect'

eval-all: eval-engineer eval-boss eval-architect

# ─── Autoresearch: Launch prompt optimization loops ───────────

AR_DIR = /workspace/repos/opencode-pai/.autoresearch

research-engineer:
	docker compose exec -d opencode-pai bash -c \
		'cd /workspace/repos/opencode-pai && \
		 rm -f $(AR_DIR)/STOP-pai-engineer $(AR_DIR)/checkpoint-pai-engineer.json && \
		 EVAL_AGENT=pai-engineer bash $(AR_DIR)/loop.sh > $(AR_DIR)/output-pai-engineer-latest.log 2>&1'
	@echo "pai-engineer autoresearch launched. Monitor: make research-status"

research-boss:
	docker compose exec -d opencode-pai bash -c \
		'cd /workspace/repos/opencode-pai && \
		 rm -f $(AR_DIR)/STOP-pai-boss $(AR_DIR)/checkpoint-pai-boss.json && \
		 EVAL_AGENT=pai-boss bash $(AR_DIR)/loop.sh > $(AR_DIR)/output-pai-boss-latest.log 2>&1'
	@echo "pai-boss autoresearch launched. Monitor: make research-status"

research-architect:
	docker compose exec -d opencode-pai bash -c \
		'cd /workspace/repos/opencode-pai && \
		 rm -f $(AR_DIR)/STOP-pai-architect $(AR_DIR)/checkpoint-pai-architect.json && \
		 EVAL_AGENT=pai-architect bash $(AR_DIR)/loop.sh > $(AR_DIR)/output-pai-architect-latest.log 2>&1'
	@echo "pai-architect autoresearch launched. Monitor: make research-status"

research-all: research-engineer research-boss research-architect
	@echo "All three autoresearch loops launched in parallel."

research-stop:
	docker compose exec opencode-pai bash -c \
		'cd /workspace/repos/opencode-pai && \
		 touch $(AR_DIR)/STOP-pai-engineer $(AR_DIR)/STOP-pai-boss $(AR_DIR)/STOP-pai-architect'
	@echo "Stop files created. Loops will halt after current experiment."

research-status:
	@echo "═══ Autoresearch Status ═══"
	@docker compose exec opencode-pai bash -c '\
		cd /workspace/repos/opencode-pai/.autoresearch && \
		for agent in pai-engineer pai-boss pai-architect; do \
			echo ""; \
			echo "─── $$agent ───"; \
			if [ -f "checkpoint-$$agent.json" ]; then \
				cat "checkpoint-$$agent.json" 2>/dev/null; echo ""; \
			else \
				echo "  No checkpoint (not started or completed)"; \
			fi; \
			if [ -f "baseline-$$agent.txt" ]; then \
				echo "  Baseline: $$(cat baseline-$$agent.txt)"; \
			fi; \
			LOG=$$(ls -t output-$$agent-*.log 2>/dev/null | head -1); \
			if [ -n "$$LOG" ]; then \
				echo "  Latest log: $$LOG"; \
				tail -3 "$$LOG" 2>/dev/null | sed "s/^/  /"; \
			fi; \
			if [ -f "STOP-$$agent" ]; then \
				echo "  ⏹  STOP file present"; \
			fi; \
		done; \
		echo ""; \
		echo "─── Processes ───"; \
		ps aux | grep loop.sh | grep -v grep | wc -l | xargs -I{} echo "  {} loop.sh processes running"'
