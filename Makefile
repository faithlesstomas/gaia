GAIA_LLM_URL ?= http://localhost:4000
GAIA_MODEL ?= gemma4:e2b
GAIA_BASE_MODEL ?= gemma4:e2b

export GAIA_LLM_URL
export GAIA_MODEL
export GAIA_BASE_MODEL

.PHONY: run repl check test-units test-rlm test-tool-use benchmark dataset clean llm-server llm-server-stop clean-trajectories monitor client server

GUIX_SHELL = guix shell -m guix.scm --

run: llm-server
	@echo "\033[1;31mERROR: 'make run' is deprecated because 'make' intercepts Ctrl-C and breaks the REPL.\033[0m"
	@echo "\033[1;32mPlease run the CLI directly using:\033[0m ./bin/gaia"
	@exit 1

repl:
	$(GUIX_SHELL) guile -L src

check: test-units test-tools test-rlm-env test-sessions test-meta-commands

test-meta-commands:
	@echo "Running GAIA meta-command integration tests..."
	$(GUIX_SHELL) guile -L src tests/test-meta-commands.scm

test-units:
	@echo "Running core unit tests..."
	$(GUIX_SHELL) guile -L src scripts/test-units.scm
	@echo "Running history and meta-command tests..."
	$(GUIX_SHELL) guile -L src scripts/test-history.scm
	@echo "Running signal extraction tests..."
	$(GUIX_SHELL) guile -L src scripts/test-final-signal.scm
	@echo "Running error handling tests..."
	$(GUIX_SHELL) guile -L src scripts/test-error-handling.scm

test-tools:
	@echo "Running tools unit tests..."
	$(GUIX_SHELL) guile -L src scripts/test-tools.scm

test-rlm-env:
	@echo "Running RLM environment unit tests..."
	$(GUIX_SHELL) guile -L src scripts/test-rlm-env.scm

test-sessions:
	@echo "Running GAIA session management unit tests..."
	$(GUIX_SHELL) guile -L src -L tests tests/test-sessions.scm

llm-server:
	@if nc -z localhost 4000 2>/dev/null; then \
		echo "LiteLLM server is already running on port 4000."; \
	else \
		echo "Starting LiteLLM server..."; \
		uv run litellm --config litellm_config.yaml --port 4000 > .litellm.log 2>&1 & echo $$! > .litellm.pid; \
		sleep 6; \
	fi

llm-server-stop:
	@echo "Stopping LiteLLM server..."
	-kill `cat .litellm.pid` 2>/dev/null || true
	-pkill -f "litellm --config litellm_config.yaml" 2>/dev/null || true
	rm -f .litellm.pid

test-rlm: llm-server
	@echo "Running RLM pipeline sanity check (requires LLM server)..."
	$(GUIX_SHELL) guile -L src scripts/test-sanity.scm; \
	STATUS=$$?; \
	$(MAKE) llm-server-stop; \
	exit $$STATUS

test-tool-use: llm-server
	@echo "Running LLM tool-use test: search-file needle (requires LLM server)..."
	BENCHMARK_SIZE_MB=1 $(GUIX_SHELL) guile -L src scripts/test-tool-use.scm; \
	STATUS=$$?; \
	$(MAKE) llm-server-stop; \
	exit $$STATUS

benchmark:
	@echo "Running S-NIAH Benchmark — RLM recursion via context chunking + llm_query..."
	@echo "  Context size: $${BENCHMARK_SIZE_KB:-512}KB"
	BENCHMARK_SIZE_KB=$${BENCHMARK_SIZE_KB:-512} $(GUIX_SHELL) guile -L src scripts/benchmark-niah.scm

dataset:
	@FILE=$${FILE:-$$(cat .last_trajectory 2>/dev/null || ls -t trajectories-*.jsonl 2>/dev/null | head -n1 || echo "trajectories.jsonl")}; \
	echo "Curating dataset from: $$FILE"; \
	$(GUIX_SHELL) guile -L src -c "(use-modules (gaia curator)) (curate-dataset \"$$FILE\" \"dataset-success.jsonl\" \"dataset-failure.jsonl\")"

learn:
	@echo "Curating dataset locally..."
	@$(MAKE) dataset
	@echo "Triggering local training pipeline..."
	@echo "TODO: Execute local python training script here... (e.g. uv run python scripts/train.py --dataset dataset-success.jsonl)"


clean:
	rm -f *.go dataset-*.jsonl

clean-trajectories:
	rm -f trajectories.jsonl

monitor:
	@FILE=$${FILE:-$$(cat .last_trajectory 2>/dev/null || ls -t trajectories-*.jsonl 2>/dev/null | head -n1 || echo "trajectories.jsonl")}; \
	echo "Monitoring GAIA Trajectory: $$FILE"; \
	$(GUIX_SHELL) guile -L src scripts/gaia-monitor.scm $$FILE

client:
	@echo "Building and running GAIA Rust Client..."
	$(GUIX_SHELL) cargo run --manifest-path src/gaia-cli/Cargo.toml

server:
	@echo "Starting GAIA Headless Server..."
	$(GUIX_SHELL) ./bin/gaia-server

serwer: server
