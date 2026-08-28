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
| Exact arithmetic `(17 × 3) − 9` | `arithmetic-42@1` | Complete Guile Action returning one datum | `EXACT_VALUE`: result equals `42` | Covered | `arithmetic-42` | Candidate; repeated baseline pending |
| Square fixed list `(1 2 3 4 5)` | `map-squares@1` | Complete Guile Action returning one list | `STRUCTURED_VALUE`: exact list equality | Covered | `map-squares` | Candidate; repeated baseline pending |
| Filter evens from fixed list | `filter-evens@1` | Complete Guile Action returning one list | `STRUCTURED_VALUE`: exact list equality | Covered | `filter-evens` | Candidate; repeated baseline pending |
| Recursive factorial of 6 | `factorial-6@1` | Define `factorial`; return one datum | Required binding plus `EXACT_VALUE` result | Covered | `factorial-6` | Candidate; repeated baseline pending |
| First ten Fibonacci terms | `fibonacci-10@1` | Define `fibonacci-sequence`; return one list | Required binding plus `STRUCTURED_VALUE` result | Covered | `fibonacci-10` | Candidate; repeated baseline pending |

These are deliberately narrow executable contracts, not claims of general
arithmetic, general list processing, or general programming competence.

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
- reported first-pass and post-repair success, calls, executions, tokens, and
  latency.

A capability that misses its cell threshold MUST be marked experimental or
removed from the advertised release matrix. Overall averages MUST NOT hide a
failing capability cell.

## Explicitly unsupported in the MVP

The MVP does not advertise generic filesystem mutation, shell execution,
network writes, external communication, purchases, physical control,
self-modification, open-ended factual answering, or LLM-only verification.
Read-only experimental NCSI observations do not expand this capability matrix.
