GAIA_LLM_URL ?= http://localhost:4000
GAIA_MODEL ?= gemma4:e2b
GAIA_BASE_MODEL ?= gemma4:e2b
GAIA_ALLOW_SANDBOX_FALLBACK ?= 1

export GAIA_LLM_URL
export GAIA_MODEL
export GAIA_BASE_MODEL
export GAIA_ALLOW_SANDBOX_FALLBACK

.PHONY: run repl check test-units test-sandbox test-tools test-rlm-env test-sessions test-meta-commands test-actors test-server test-rlm test-tool-use benchmark dataset clean llm-server llm-server-stop clean-trajectories monitor client server gcas-showcase gcas-eval gcas-live-eval gcas-conformance gcas-conformance-scheme test-clients test-emacs-client

GUIX_SHELL = guix shell -m guix.scm --
GUIX_DEV_SHELL = guix shell -m guix-dev.scm --

run: llm-server
	@echo "\033[1;31mERROR: 'make run' is deprecated because 'make' intercepts Ctrl-C and breaks the REPL.\033[0m"
	@echo "\033[1;32mPlease run the CLI directly using:\033[0m ./bin/gaia"
	@exit 1

repl:
	$(GUIX_SHELL) guile -L src

check:
	@echo "Running GAIA test suite..."
	GAIA_NO_COVERAGE=1 $(GUIX_SHELL) guile -L src tests/run-coverage.scm

gcas-showcase:
	GUILE_AUTO_COMPILE=0 guile -L src scripts/run-gcas-showcase.scm

gcas-eval:
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-gcas-eval-corpus.scm

gcas-live-eval:
	GUILE_AUTO_COMPILE=0 guile -L src scripts/run-gcas-live-eval.scm

ncsi-eval:
	GUILE_AUTO_COMPILE=0 guile -L src scripts/run-ncsi-evaluation.scm

test-clients:
	cargo test --manifest-path src/gaia-cli/Cargo.toml
	$(MAKE) test-emacs-client

test-emacs-client:
	emacs --batch -Q -L src/gaia-desktop/emacs -l tests/test-emacs-client.el

gcas-conformance-scheme:
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-goal-verifier.scm
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-cognitive-memory.scm
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-cognitive-session.scm
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-production-processors.scm
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-ncsi.scm
	$(MAKE) gcas-eval
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-server.scm
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-actors.scm

test-ncsi:
	@echo "Running NCSI and J-space processor unit tests..."
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-ncsi.scm
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-ncsi-evaluation.scm
	GUILE_AUTO_COMPILE=0 guile -L src tests/test-rai-ncsi-adapter.scm

gcas-conformance: gcas-conformance-scheme
	$(MAKE) test-clients

test-server:
	@echo "Running GAIA server unit tests..."
	$(GUIX_SHELL) guile -L src tests/test-server.scm

test-curator:
	@echo "Running GAIA curator unit tests..."
	$(GUIX_SHELL) guile -L src tests/test-curator.scm

test-llm-client:
	@echo "Running GAIA LLM client unit tests..."
	$(GUIX_SHELL) guile -L src tests/test-llm-client.scm

test-meta-commands:
	@echo "Running GAIA meta-command integration tests..."
	$(GUIX_SHELL) guile -L src tests/test-meta-commands.scm

test-actors:
	@echo "Running GAIA Goblins actors unit tests..."
	$(GUIX_SHELL) guile -L src tests/test-actors.scm

test-units:
	@echo "Running core unit tests..."
	$(GUIX_SHELL) guile -L src tests/test-units.scm
	@echo "Running history and meta-command tests..."
	$(GUIX_SHELL) guile -L src tests/test-history.scm
	@echo "Running signal extraction tests..."
	$(GUIX_SHELL) guile -L src tests/test-final-signal.scm
	@echo "Running error handling tests..."
	$(GUIX_SHELL) guile -L src tests/test-error-handling.scm
	@echo "Running static safety validator tests..."
	$(GUIX_SHELL) guile -L src tests/test-safety.scm
	@echo "Running RLM delegation tests..."
	$(GUIX_SHELL) guile -L src tests/test-delegation.scm
	@echo "Running interrupt handler tests..."
	$(GUIX_SHELL) guile -L src tests/test-interrupts.scm
	@echo "Running error traceback capture tests..."
	$(GUIX_SHELL) guile -L src tests/test-traceback.scm

test-sandbox:
	@echo "Running Goblins sandbox unit tests..."
	$(GUIX_SHELL) guile -L src tests/test-sandbox.scm

test-tools:
	@echo "Running tools unit tests..."
	$(GUIX_SHELL) guile -L src tests/test-tools.scm

test-rlm-env:
	@echo "Running RLM environment unit tests..."
	$(GUIX_SHELL) guile -L src tests/test-rlm-env.scm

test-sessions:
	@echo "Running GAIA session management unit tests..."
	$(GUIX_SHELL) guile -L src -L tests tests/test-sessions.scm

test-coverage:
	@echo "Cleaning compilation cache..."
	rm -rf ~/.cache/guile/ccache
	@echo "Warming up compilation cache with debug info..."
	GAIA_NO_COVERAGE=1 $(GUIX_SHELL) guile --debug -L src tests/run-coverage.scm
	@echo "Running full GAIA test suite with code coverage..."
	$(GUIX_SHELL) guile --debug -L src tests/run-coverage.scm
	@if command -v genhtml >/dev/null 2>&1; then \
		echo "Generating HTML coverage report under coverage-html/..."; \
		genhtml coverage.info --output-directory coverage-html; \
	else \
		echo "genhtml not found. For visual HTML reports, install lcov package."; \
	fi

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
	$(GUIX_SHELL) guile -L src tests/test-sanity.scm; \
	STATUS=$$?; \
	$(MAKE) llm-server-stop; \
	exit $$STATUS

test-tool-use: llm-server
	@echo "Running LLM tool-use test: search-file needle (requires LLM server)..."
	BENCHMARK_SIZE_MB=1 $(GUIX_SHELL) guile -L src tests/test-tool-use.scm; \
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
	$(GUIX_DEV_SHELL) cargo run --manifest-path src/gaia-cli/Cargo.toml

server:
	@echo "Starting GAIA Headless Server..."
	$(GUIX_SHELL) ./bin/gaia-server

serwer: server
