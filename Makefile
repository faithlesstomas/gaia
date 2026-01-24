.PHONY: run repl test-units test-rlm dataset clean

GUIX_SHELL = guix shell -m guix.scm --

run:
	$(GUIX_SHELL) guile -L scheme scripts/run-gaia.scm

repl:
	$(GUIX_SHELL) guile -L scheme

test-units:
	$(GUIX_SHELL) guile -L scheme scripts/test-units.scm

test-rlm:
	$(GUIX_SHELL) guile -L scheme scripts/test-rlm.scm

dataset:
	$(GUIX_SHELL) guile -L scheme -c '(use-modules (gaia curator)) (curate-dataset "trajectories.jsonl" "dataset-success.jsonl" "dataset-failure.jsonl")'

clean:
	rm -f *.go dataset-*.jsonl
