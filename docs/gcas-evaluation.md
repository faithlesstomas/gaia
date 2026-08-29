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

The corpus contains 23 cases across first-pass completion, preflight syntax,
runtime syntax and verifier repair, planning failures, verification rejection and
inconclusiveness, repeated Actions, all Control budgets, adapter failure, user
interruption, and a success callback arriving after interruption.

## Metrics and baseline

The runner prints a result row for every fixture and a summary containing case
counts, hangs, false completions, repair success, model calls, executions, and
latency. The initial deterministic baseline is:

```text
cases=23 passed=23 failed=0 hangs=0 false-completions=0
repair-success=5/5 model-calls=33 executions=26
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
tasks, execution environment, and hidden behavioral verifiers are reused for
every configured model. It is deliberately excluded from `make check` and
`make gcas-conformance`, so offline CI neither requires a model server nor incurs
remote inference cost.

The eval-v2 corpus contains arithmetic, list mapping, list filtering,
recursive factorial, and Fibonacci procedure contracts. It performs no filesystem mutation
and denies permission-gated sandbox capabilities. Configure the matrix with:

```sh
# One explicitly approved model, one run of every task
GAIA_EVAL_MODELS='qwen3:4b' \
GAIA_EVAL_MODEL_PARAMETERS_B=4 \
GAIA_EVAL_RESOURCE_APPROVED=1 \
make gcas-live-eval

# One model and three repetitions per capability cell
GAIA_EVAL_MODELS='qwen3:4b' \
GAIA_EVAL_MODEL_PARAMETERS_B=4 \
GAIA_EVAL_RESOURCE_APPROVED=1 \
GAIA_EVAL_REPEATS=3 \
make gcas-live-eval

# A subset, explicit reasoning mode, and a machine-readable report
GAIA_EVAL_TASKS='arithmetic-42,fibonacci-10' \
GAIA_EVAL_MODELS='qwen3:4b' \
GAIA_EVAL_MODEL_PARAMETERS_B=4 \
GAIA_EVAL_RESOURCE_APPROVED=1 \
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

### Hidden behavioral oracle (eval v2)

The five former fixed-output tasks retain their stable task IDs, but now require
procedures: `solve-arithmetic(a,b,c)`, `square-all(xs)`, `keep-evens(xs)`,
`factorial(n)`, and `fibonacci-sequence(n)`. Prompts and repair feedback expose
only these public signatures and semantics.

At the execution boundary the evaluator appends a private deterministic harness
to the submitted Action. Probe selection is seeded by repetition; a repaired
Action receives an expanded suite with fresh holdout inputs. Only aggregate
passed/failed counts reach the Goal verifier. Failing inputs and oracle values
are never projected into model or repair context.

Report schema v2 records `lifecycle_ok`, `action_executed`,
`hidden_tests_passed`, and `hidden_tests_run` separately. Readiness rejects
legacy v1 results and any completion not established by hidden tests. Simple
literals and fixed lookup answers are covered by deterministic regressions.
This does not prove robustness against deliberately adversarial code; broader
held-out datasets remain a stronger boundary than static source inspection.

The runner refuses multiple models, models declared above 4B parameters, and
all invocations without `GAIA_EVAL_RESOURCE_APPROVED=1`. This flag is set only
after explicit operator approval for that run. Registering several aliases in
LiteLLM is not permission to load them; the benchmark sends requests to exactly
one model. Offline tests never contact Ollama or LiteLLM.

### Live observability

Long evaluations can expose bounded, non-semantic diagnostics without changing
the GCAS event log or benchmark trajectory. `GAIA_EVAL_VERBOSE` accepts four
levels:

- `0` keeps the final per-run, cell, summary, and readiness output;
- `1` adds matrix progress, model-call start/end, a waiting heartbeat, Action
  execution, and an immediate result for every completed case;
- `2` additionally prints every durable GCAS event with its CO preview, Control
  counters, and Global Workspace pending/active identifiers;
- `3` additionally prints complete prompts, model responses, Actions, Results,
  and actual processor receive/return routing. This level may expose sensitive
  prompt or memory content and should be stored accordingly.

The supporting controls are:

```sh
GAIA_EVAL_VERBOSE=2                    # 0..3
GAIA_EVAL_HEARTBEAT_SECONDS=10        # positive integer
GAIA_EVAL_PREVIEW_CHARS=240           # level-1/2 console preview bound
GAIA_EVAL_TRACE_OUTPUT=/tmp/gcas.jsonl # flushed after every diagnostic
```

The JSONL trace contains every enabled diagnostic and embeds the complete result
of each finished case. It therefore preserves completed work when the outer
command is interrupted before the final JSON report is written. Verbosity is an
observer only: callback failures are isolated, processor diagnostics are not
stored in Cognitive State or published on the Bus, and enabling logging must not
change readiness metrics.

The evaluation runner calls LiteLLM directly; it does not pass through the GAIA
headless server and therefore does not produce `gaia-server.log`. When LiteLLM
was started with `make llm-server`, its independent process log can be followed
in another terminal with:

```sh
make llm-server-logs
```

Readiness continues to use non-streaming inference so verbosity cannot change
the measured transport path or token accounting. The heartbeat reports that a
request is still pending, while full model output appears after the endpoint
returns.

For example, a fully observable smoke test is:

```sh
GAIA_EVAL_MODELS='qwen3-4b-eval' \
GAIA_EVAL_MODEL_PARAMETERS_B=4 \
GAIA_EVAL_RESOURCE_APPROVED=1 \
GAIA_EVAL_TASKS='arithmetic-42' \
GAIA_EVAL_REPEATS=1 \
GAIA_EVAL_VERBOSE=3 \
GAIA_EVAL_HEARTBEAT_SECONDS=10 \
GAIA_EVAL_TRACE_OUTPUT=/tmp/gcas-qwen3-smoke.jsonl \
GAIA_EVAL_OUTPUT=/tmp/gcas-qwen3-smoke.json \
make gcas-live-eval
```

The production Action adapter accepts `scheme` fences as a normalization alias
for the contract's preferred `repl` fence. This is intentionally scoped to GCAS:
the legacy notebook extractor remains strict, and normalized Actions still pass
through policy, sandbox execution, evidence, and independent verification.

An exploratory one-shot `gemma4:e2b` eval-v1 run on 2026-08-14 first scored 0/5 because
all five otherwise actionable responses used `scheme` fences. After adapter
normalization, the identical matrix scored 3/5: arithmetic and factorial passed
on the first Action, list mapping passed after repair, and list filtering plus
Fibonacci exhausted the three-failure budget. All five lifecycles terminated
correctly. This is diagnostic evidence, not a readiness baseline. All eval-v1
reports are invalid as readiness evidence because fixed oracle values allowed
hardcoded implementations.

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
