# GAIA MVP capability and readiness matrix

This document is the release-facing scope boundary for the GAIA Persistent
Verified Assistant MVP. A capability is **advertised** only when it has a
versioned manifest, intent matcher, Goal acceptance contract, Action schema,
independent verifier, deterministic fixture, live evaluation case, and measured
readiness result.

Unknown or ambiguous intents fail closed as `INCONCLUSIVE`; they are not routed
to a generic LLM judge.

## Candidate executable capabilities

| Capability | Manifest | Action boundary | Independent verifier | Deterministic gate | Live gate | Release status |
|---|---|---|---|---|---|---|
| Arithmetic relation `(a × b) − c` | production v2; eval v2 | Define `solve-arithmetic(a,b,c)` | Private inputs plus repair holdout | Covered, including shortcut rejection | `arithmetic-42` v2 | Implemented; repeated baseline pending |
| Square arbitrary numeric lists | production v2; eval v2 | Define `square-all(xs)` | Private lists plus repair holdout | Covered, including shortcut rejection | `map-squares` v2 | Implemented; repeated baseline pending |
| Filter evens from integer lists | production v2; eval v2 | Define `keep-evens(xs)` | Private lists plus repair holdout | Covered, including shortcut rejection | `filter-evens` v2 | Implemented; repeated baseline pending |
| Factorial for non-negative integers | production v2; eval v2 | Define `factorial(n)` | Private boundary and general inputs | Covered, including constant rejection | `factorial-6` v2 | Implemented; repeated baseline pending |
| Fibonacci prefix for non-negative length | production v2; eval v2 | Define `fibonacci-sequence(n)` | Private lengths plus repair holdout | Covered, including lookup rejection | `fibonacci-10` v2 | Implemented; repeated baseline pending |

The live contracts test bounded generalization within these procedure families;
they are not claims of general programming or mathematical competence. Normal
production `solve` and eval v2 share the private-harness evidence boundary.
Production probes are attempt-seeded; the live matrix additionally seeds cells
by repetition and records hidden-test metrics.

## Ordinary assistant capability

Natural-language conversation is a product capability but not an executable
capability in the table above. Plain input runs a bounded GCAS Cognitive Process,
persists typed dialogue COs, reconstructs context after restart with empty LLM
history, and verifies only response delivery. Assistant prose remains
`HYPOTHESIS`/`UNVERIFIED`. Its deterministic conformance gate is covered. The
operator-approved two-turn gate passed on `qwen3.5-4b` with zero provider
history and bounded restored Memory; see
[the evaluation report](evaluations/gcas-conversation-qwen3.5-4b-mvp.md).

## Reusable verifier classes

The registry additionally provides reusable, independently testable verifier
contracts for:

- `EXACT_VALUE`;
- `STRUCTURED_VALUE`;
- `PREDICATE_PROPERTY`;
- `UNIT_TEST` summaries;
- content-addressed `ARTIFACT` observations;
- fresh `ENVIRONMENT_STATE` observations;
- exact-scope `HUMAN_APPROVAL` records.

Availability of a verifier class does not advertise a capability. Each new
capability still requires its own manifest, fixtures, live case, and threshold.

## MVP readiness thresholds

The deterministic release gate requires:

- 100% expected fixture outcomes;
- zero hangs;
- zero false completions;
- exactly one terminal event and callback per process;
- 100% success for designated repair trajectories;
- green Rust and Emacs protocol tests.

The live release gate for the default model requires, for every advertised
capability:

- at least 10 independent repetitions under the published model, prompt,
  thinking mode, endpoint, and runtime revisions;
- 100% terminal-response rate;
- zero false completions;
- at least 80% verified task success per capability cell;
- bounded interruption latency with no post-terminal execution;
- no repeated Action execution;
- eval-v2 hidden tests for every successful completion, with fresh holdout
  probes after repair;
- reported first-pass and post-repair success, calls, executions, tokens, and
  latency.

A capability that misses its cell threshold MUST be marked experimental or
removed from the advertised release matrix. Overall averages MUST NOT hide a
failing capability cell.

Eval-v1 reports are diagnostic-only and cannot contribute repetitions to this
release gate.

## Explicitly unsupported in the MVP

The MVP does not advertise generic filesystem mutation, shell execution,
network writes, external communication, purchases, physical control,
self-modification, open-ended factual answering, or LLM-only verification.
Read-only experimental NCSI observations do not expand this capability matrix.
