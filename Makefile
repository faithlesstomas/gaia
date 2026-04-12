GAIA_LLM_URL ?= http://localhost:4000
GAIA_MODEL ?= gemma4:e4b
GAIA_BASE_MODEL ?= gemma4:e4b

export GAIA_LLM_URL
export GAIA_MODEL
export GAIA_BASE_MODEL

.PHONY: run repl check test-units test-rlm test-tool-use benchmark dataset clean llm-server llm-server-stop

GUIX_SHELL = guix shell -m guix.scm --

run:
	$(GUIX_SHELL) guile -L scheme scripts/run-gaia.scm

repl:
	$(GUIX_SHELL) guile -L scheme

check: test-units test-tools test-rlm-env

test-units:
	@echo "Running core unit tests..."
	$(GUIX_SHELL) guile -L scheme scripts/test-units.scm
	@echo "Running signal extraction tests..."
	$(GUIX_SHELL) guile -L scheme scripts/test-final-signal.scm
	@echo "Running error handling tests..."
	$(GUIX_SHELL) guile -L scheme scripts/test-error-handling.scm

test-tools:
	@echo "Running tools unit tests..."
	$(GUIX_SHELL) guile -L scheme scripts/test-tools.scm

test-rlm-env:
	@echo "Running RLM environment unit tests..."
	$(GUIX_SHELL) guile -L scheme scripts/test-rlm-env.scm

llm-server:
	@echo "Starting LiteLLM server..."
	uv run litellm --config litellm_config.yaml --port 4000 > .litellm.log 2>&1 & echo $$! > .litellm.pid
	sleep 2

llm-server-stop:
	@echo "Stopping LiteLLM server..."
	-kill `cat .litellm.pid` 2>/dev/null || true
	-pkill -f "litellm --config litellm_config.yaml" 2>/dev/null || true
	rm -f .litellm.pid

test-rlm: llm-server
	@echo "Running RLM pipeline sanity check (requires LLM server)..."
	$(GUIX_SHELL) guile -L scheme scripts/test-sanity.scm; \
	STATUS=$$?; \
	$(MAKE) llm-server-stop; \
	exit $$STATUS

test-tool-use: llm-server
	@echo "Running LLM tool-use test: search-file needle (requires LLM server)..."
	BENCHMARK_SIZE_MB=1 $(GUIX_SHELL) guile -L scheme scripts/test-tool-use.scm; \
	STATUS=$$?; \
	$(MAKE) llm-server-stop; \
	exit $$STATUS

benchmark:
	@echo "Running S-NIAH Benchmark — RLM recursion via context chunking + llm_query..."
	@echo "  Context size: $${BENCHMARK_SIZE_KB:-512}KB"
	BENCHMARK_SIZE_KB=$${BENCHMARK_SIZE_KB:-512} $(GUIX_SHELL) guile -L scheme scripts/benchmark-niah.scm

dataset:
	$(GUIX_SHELL) guile -L scheme -c '(use-modules (gaia curator)) (curate-dataset "trajectories.jsonl" "dataset-success.jsonl" "dataset-failure.jsonl")'

learn:
	@echo "Curating dataset locally..."
	@$(MAKE) dataset
	@echo "Triggering local training pipeline..."
	@echo "TODO: Execute local python training script here... (e.g. uv run python scripts/train.py --dataset dataset-success.jsonl)"


clean:
	rm -f *.go dataset-*.jsonl

clean-trajectories:
	rm -f trajectories.jsonl
