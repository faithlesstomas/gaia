GAIA_RAI_URL ?= http://localhost:8000
GAIA_MODEL ?= gemma3:12b
GAIA_BACKEND ?= ollama
GAIA_BASE_MODEL ?= gemma-3-4b

export GAIA_RAI_URL
export GAIA_MODEL
export GAIA_BACKEND
export GAIA_BASE_MODEL

.PHONY: run repl check test-units test-rlm test-tool-use benchmark dataset clean

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

test-rlm:
	@echo "Running RLM pipeline sanity check (requires RAI server)..."
	$(GUIX_SHELL) guile -L scheme scripts/test-sanity.scm

test-tool-use:
	@echo "Running LLM tool-use test: search-file needle (requires RAI server)..."
	BENCHMARK_SIZE_MB=1 $(GUIX_SHELL) guile -L scheme scripts/test-tool-use.scm

benchmark:
	@echo "Running S-NIAH Benchmark — RLM recursion via context chunking + llm_query..."
	@echo "  Context size: $${BENCHMARK_SIZE_KB:-512}KB"
	BENCHMARK_SIZE_KB=$${BENCHMARK_SIZE_KB:-512} $(GUIX_SHELL) guile -L scheme scripts/benchmark-niah.scm

dataset:
	$(GUIX_SHELL) guile -L scheme -c '(use-modules (gaia curator)) (curate-dataset "trajectories.jsonl" "dataset-success.jsonl" "dataset-failure.jsonl")' $(if $(GAIA_RAI_URL), --push-to-rai $(GAIA_RAI_URL))

learn:
	@echo "Curating and pushing to RAI..."
	@$(MAKE) dataset GAIA_RAI_URL=$(GAIA_RAI_URL)
	@echo "Triggering training..."
	@curl -X POST -H "Content-Type: application/json" -d '{"base_model": "$(GAIA_BASE_MODEL)", "dataset_id": "dataset-success.jsonl"}' $(GAIA_RAI_URL)/train/start | jq
	@echo "Check staus with:"
	@echo "curl $(GAIA_RAI_URL)/train/status/{job_id}"


clean:
	rm -f *.go dataset-*.jsonl

clean-trajectories:
	rm -f trajectories.jsonl
