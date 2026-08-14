# GCAS prompt projection and small-model strategy

## Current behavior

Production `solve` does not replay the session transcript as an LLM
conversation. The Session Orchestrator calls the Generative Processor with:

- `get-gcas-system-prompt` as a compact stable system contract;
- a transient user/context prompt reconstructed from Cognitive Objects;
- an empty chat-history list.

The initial projection contains the current Goal, admitted Workspace objects,
lexically selected structured Memory, completion criteria, and active
constraints. After a failed Action or verifier conflict, the next projection
adds the relevant Reflection and exact execution feedback. The complete history
remains available for audit and UI, but it is not treated as cognitive memory.

This satisfies the GCAS separation between transcript and Memory. Production
`solve` no longer receives the legacy RLM completion protocol: its dedicated
contract explicitly forbids `FINAL`, `FINAL_VAR`, and `CONFIDENCE`, because the
GCAS Answer Processor and Goal Verifier own terminal decisions. The legacy
solver prompt remains available only to the `investigate` compatibility path.

The current contract also states the transactional execution boundary, requires
one complete distinct Action, prefers a returned value, and includes compact
Guile rules for `if`, bindings, and `set!`. Wisp instructions are appended only
when Wisp mode is enabled. An explicit `GAIA_SYSTEM_PROMPT` override still wins.

## Design decision

Use a **small stable contract plus dynamic state projections**, not an
ever-growing dynamic system prompt.

The stable system contract should contain only invariants:

1. the model proposes an unverified Hypothesis or executable Action;
2. the required output schema, normally one short `repl` block;
3. available Guile/tool capabilities and hard safety restrictions;
4. the rule that execution and verification outcomes come from GAIA, not from
   model assertions;
5. concise Scheme patterns known to be valid for the configured runtime.

The dynamic projection is generated deterministically from typed state and
already distinguishes initial generation from repair. It should evolve into
more structured phase projections:

- **Initial generation:** Goal, executable acceptance criteria, relevant facts,
  capability manifest, and remaining budgets.
- **Syntax repair:** exact rejected Action, Guile error class and failing form,
  a request for one complete distinct replacement, and a bias toward simpler
  syntax.
- **Runtime repair:** exact input/output or exception, reproducibility metadata,
  changed assumptions, and the still-unsatisfied criterion.
- **Verifier repair:** observed successful execution, rejected property, verifier
  rationale, and the smallest unmet acceptance condition.

Raw transcript turns should not be reintroduced merely to make the prompt look
conversational. If a prior fact or result matters, it should be selected as a CO
with provenance and projected explicitly.

## Working with tool-oriented local models

The default `gemma4:e2b` model is small and trained primarily for tool use, not
for maintaining a long-lived Guile REPL program. Its Scheme-generation failures
also occurred in the legacy RLM loop, so they should not be attributed solely to
GCAS context reconstruction.

Near-term adaptations should exploit the model's strengths:

- present Action requests in a tool-like schema and map them to Action COs;
- prefer high-level, preloaded procedures over handwritten nested Scheme;
- preflight parsing before mutating the persistent environment;
- return short structured errors rather than a transcript dump;
- require a fresh complete Action after syntax failure;
- make capability and verifier availability explicit before generation.

Native model tool calls can later become another Generative/Planner adapter.
They should still cross the same Action, policy, execution, evidence, and
verification boundaries.

## NCSI and J-space

NCSI/J-space could provide a stronger bidirectional channel for selecting or
steering internal neural state, especially when textual feedback does not focus
a small model reliably. It is not required for GCAS-Core and cannot by itself
guarantee valid Scheme or correct tool use.

The implementation should therefore preserve one projection interface with
multiple possible adapters:

```text
typed Cognitive State
        |
        +-- textual phase projection (current)
        +-- native tool/action schema (near term)
        +-- NCSI/J-space steering adapter (research)
```

This lets evaluation compare adapters without changing Control, Workspace,
Memory, execution, or verification semantics.

## Evaluation rule

Do not tune the prompt from a single Fibonacci trajectory. Establish a small
versioned task corpus and compare prompt/projection variants on:

- terminal-response rate and hangs;
- first-pass and post-repair task success;
- false `COMPLETED` outcomes;
- repeated or non-progressing Actions;
- attempts, tokens, latency, and model calls.

Prompt changes should be promoted only when they improve the corpus without
weakening deterministic completion and verification invariants.

`make gcas-eval` is the model-free invariant baseline. It exercises 22 scripted
generation/execution/verifier trajectories through the production processor and
must remain green for any prompt or projection change. It does not measure how
often a real model chooses the scripted good Action; a second, live-model matrix
will reuse these task classes to compare prompt and adapter variants against the
configured local model. See [gcas-evaluation.md](gcas-evaluation.md).
