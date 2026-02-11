.PHONY: run repl check test-units test-rlm benchmark dataset clean

GUIX_SHELL = guix shell -m guix.scm --

run:
	$(GUIX_SHELL) guile -L scheme scripts/run-gaia.scm

repl:
	$(GUIX_SHELL) guile -L scheme

check: test-units

test-units:
	@echo "Running core unit tests..."
	$(GUIX_SHELL) guile -L scheme scripts/test-units.scm
	@echo "Running signal extraction tests..."
	$(GUIX_SHELL) guile -L scheme scripts/test-final-signal.scm
	@echo "Running error handling tests..."
	$(GUIX_SHELL) guile -L scheme scripts/test-error-handling.scm

test-rlm:
	@echo "Running RLM functional test (Small Benchmark)..."
	BENCHMARK_SIZE_MB=1 $(GUIX_SHELL) guile -L scheme scripts/benchmark-needle.scm

benchmark:
	@echo "Running Full Benchmark..."
	BENCHMARK_SIZE_MB=10 $(GUIX_SHELL) guile -L scheme scripts/benchmark-needle.scm

dataset:
	$(GUIX_SHELL) guile -L scheme -c '(use-modules (gaia curator)) (curate-dataset "trajectories.jsonl" "dataset-success.jsonl" "dataset-failure.jsonl")'

clean:
	rm -f *.go dataset-*.jsonl

clean-trajectories:
	rm -f trajectories.jsonl

