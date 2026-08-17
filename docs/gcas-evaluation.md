# Deterministic GCAS evaluation corpus

## Purpose

`make gcas-eval` is a small, fast, model-free competence gate for the production
GCAS processor. It answers a narrower question than a live model benchmark:
given a known sequence of model proposals and execution observations, does GCAS
repair, verify, terminate, and notify the client correctly?

This separation matters for the current small local model. A regression in
Control or terminal delivery should not be confused with weak Scheme generation,
and a better prompt should not be credited for an orchestration fix.

## Fixture contract

The versioned corpus lives in `tests/test-gcas-eval-corpus.scm`. Each fixture
declares:

- model responses and their extracted Action, or an explicit missing Action;
- deterministic execution success or classified syntax/runtime failure;
- an optional independent acceptance oracle;
- Control budgets and optional interruption/late-callback behavior;
- the exact terminal outcome and expected generation/execution counts.

Every fixture additionally enforces these global invariants:

1. the process is no longer active;
2. exactly one terminal event was persisted;
3. exactly one `on-finished` callback was delivered;
4. the callback outcome equals the process outcome;
5. no unexpected adapter call occurred;
6. a case expected to fail never reports `COMPLETED`.

The initial corpus contains 22 cases across first-pass completion, syntax,
runtime and verifier repair, planning failures, verification rejection and
inconclusiveness, repeated Actions, all Control budgets, adapter failure, user
interruption, and a success callback arriving after interruption.

## Metrics and baseline

The runner prints a result row for every fixture and a summary containing case
counts, hangs, false completions, repair success, model calls, executions, and
latency. The initial deterministic baseline is:

```text
cases=22 passed=22 failed=0 hangs=0 false-completions=0
repair-success=4/4 model-calls=31 executions=25
```

Exact outcomes and attempt counts are assertions, not merely telemetry. Latency
is reported for regression observation but is not assigned a machine-independent
CI threshold yet.

## What this does not prove

A passing deterministic corpus proves lifecycle and policy behavior for its
scripted trajectories. It does not prove that `gemma4:e2b` will generate a valid
Action, measure prompt token use, or establish that GAIA is broadly useful.

The next evaluation layer should run a small advertised-capability matrix using
the real configured model. It should report first-pass and post-repair success,
terminal rate, false completion, repeated Actions, calls, tokens, and latency by
task class. Prompt, native tool-schema, and later NCSI/J-space adapters can then
be compared while reusing the deterministic corpus as the invariant floor.

## Live-model matrix

`make gcas-live-eval` implements that second layer as an opt-in benchmark. It is
model-agnostic within GAIA's current OpenAI-compatible chat adapter: the same
tasks, execution environment, and deterministic datum verifiers are reused for
every configured model. It is deliberately excluded from `make check` and
`make gcas-conformance`, so offline CI neither requires a model server nor incurs
remote inference cost.

The initial safe corpus contains arithmetic, list mapping, list filtering,
recursive factorial, and Fibonacci tasks. It performs no filesystem mutation
and denies permission-gated sandbox capabilities. Configure the matrix with:

```sh
# One model, one run of every task (defaults to GAIA_MODEL)
make gcas-live-eval

# Multiple models and three repetitions per model/task cell
GAIA_EVAL_MODELS='gemma4:e2b,another-model' \
GAIA_EVAL_REPEATS=3 \
make gcas-live-eval

# A subset, explicit reasoning mode, and a machine-readable report
GAIA_EVAL_TASKS='arithmetic-42,fibonacci-10' \
GAIA_EVAL_THINKING=1 \
GAIA_EVAL_OUTPUT=/tmp/gcas-live-eval.json \
make gcas-live-eval
```

`GAIA_LLM_URL` selects the endpoint and `GAIA_SYSTEM_PROMPT` supplies a prompt
override, exactly as in the server. `GAIA_EVAL_THINKING` is off by default so
the benchmark configuration is explicit. The report records endpoint, model names,
task names, repetitions, thinking mode, the complete effective system prompt,
per-run trajectories,
model/task cells, and per-model totals. Token counts remain zero when an endpoint
does not return the OpenAI `usage` object.

The production Action adapter accepts `scheme` fences as a normalization alias
for the contract's preferred `repl` fence. This is intentionally scoped to GCAS:
the legacy notebook extractor remains strict, and normalized Actions still pass
through policy, sandbox execution, evidence, and independent verification.

An exploratory one-shot `gemma4:e2b` run on 2026-08-14 first scored 0/5 because
all five otherwise actionable responses used `scheme` fences. After adapter
normalization, the identical matrix scored 3/5: arithmetic and factorial passed
on the first Action, list mapping passed after repair, and list filtering plus
Fibonacci exhausted the three-failure budget. All five lifecycles terminated
correctly. This is diagnostic evidence, not a readiness baseline; repeated runs
are still required.

Benchmark task failure does not make the command fail: a weak-model result is
valid measurement. The command exits non-zero only when a GCAS lifecycle
invariant fails. Readiness thresholds should be applied after a repeated baseline
has been collected, rather than chosen from a single trajectory.

## Extending the corpus

Add a fixture when introducing a new terminal outcome, repair branch, budget,
verifier class, or asynchronous adapter behavior. Keep fixtures deterministic,
bounded, and independent of network or model availability. A new advertised
capability needs both a deterministic verifier-path fixture here and a separate
live-model benchmark case.
