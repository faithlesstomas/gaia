# GCAS-Core Conformance Gap Audit

This document evaluates GAIA against the eight minimum requirements in
[GCAS §11.2](../gcas.md#112-minimal-conformance-requirements-gcas-core). It is a
gap audit, not a declaration of conformance.

**Current conclusion:** GAIA implements a substantial GCAS substrate, but the
production `solve` path is not yet operationally GCAS-Core conformant. It remains
a centrally orchestrated, single-pass LLM → optional Action → Result pipeline.

Status meanings:

- **Implemented:** present in the production path with acceptance evidence.
- **Partial:** supporting contracts exist, but production behavior does not yet
  satisfy the complete requirement.

| GCAS-Core requirement | Status | Implemented substrate | Remaining conformance gap |
|---|---|---|---|
| Explicit COs, 3-axis metadata, provenance | Implemented | `gaia com` defines immutable COs with epistemic status, verification status, confidence, temporal validity, provenance, and relations. | Expand lifecycle validation as the ontology grows; this is not a current Core blocker. |
| Hypotheses distinct from beliefs | Implemented | LLM output begins as `HYPOTHESIS`/`UNVERIFIED`; execution success does not establish the user's original claim. | Keep accepted execution observations explicitly scoped so `BeliefUpdated` cannot be mistaken for goal verification. |
| Bounded Workspace with selective admission/broadcast | Partial | The Workspace is capacity-bounded and has candidate scoring, admission, and broadcast APIs. | Production `solve` submits and immediately advances one CO at a time, so candidates do not meaningfully compete. Introduce scheduling rounds that collect multiple proposals before admission. |
| At least Generative and Deliberative processors | Partial | Processor contracts, an LLM adapter, and a deliberative verification function exist. | Production processors are not attached to the Cognitive Bus. The orchestrator calls the LLM, executor, and deliberation directly; `PLANNER` and `METACOGNITION` are currently event labels, not independent processors. |
| Memory separate from prompt history | Implemented at minimum, functionally limited | Structured CO memory is persisted separately and selected context is reconstructed without appending chat history. | Memory currently stores mainly Question/Goal COs and uses lexical overlap. Add evidence/claim consolidation, typed memory functions, and retrieval capable of preserving facts such as user-provided identity. |
| Recurrent cognitive cycle with progress and loop monitoring | Partial / blocking | Control records transition, progress, failure, stall, and interruption counters. | Production `solve` is a fixed linear sequence with no re-entry after Result, Failure, Conflict, or Reflection. Budgets belong to the long-lived session instead of a fresh cognitive process/goal. |
| Separate execution with auditable Action/Result | Implemented | An admitted Action crosses an explicit sandbox boundary; Result/Failure links to it and receives a reproducibility observation. | Extend the policy gate beyond checking only the `action` type and add richer environment manifests after Core. |
| Explicit uncertainty, time, and failure | Implemented | COs represent confidence and temporal validity; failure and inconclusive terminal states are durable. | Make goal-level uncertainty and termination rationale visible in client-facing process views. |

## Production behavior observed in the audit

The current `solve` path:

1. creates Question and Goal COs with identical text;
2. immediately admits each submitted CO;
3. reconstructs a prompt and invokes the LLM once with empty chat history;
4. stores the response as a Hypothesis;
5. optionally extracts one code block and executes it as an Action;
6. verifies only the bounded observation that the Action produced the Result;
7. returns `INSUFFICIENT_INFORMATION`, `FAILED`, or `INCONCLUSIVE`.

The event trace is valuable as a durable audit record and execution gate, but it
does not yet drive a recurrent multi-processor process. `WorkspaceBroadcast`
does not activate production processors because none are attached to the
session bus. A successful sandbox call can therefore produce a verified claim
about execution while leaving the actual task unresolved.

## Architectural boundary

The server/IPC/client topology is compatible with GCAS. The server should own
Cognitive State, Workspace, Bus, Control, Memory, processors, and execution.
The Rust CLI and Emacs client should remain thin protocol clients. IPC transports
commands and observations; it is not the Cognitive Bus itself.

## Conformance gate

GAIA may claim GCAS-Core conformance only when the production path demonstrates
all of the following in an automated vertical test:

1. a Goal has explicit completion criteria and a per-process budget;
2. production processors subscribe and react through the Cognitive Bus;
3. multiple proposals can coexist and compete before Workspace admission;
4. Result/Failure/Conflict events can trigger a subsequent planning or
   generation iteration;
5. an independent, goal-specific verifier decides whether evidence satisfies
   the Goal;
6. an Answer Processor renders only from accepted claims and the terminal goal
   state, rather than exposing raw LLM output as the answer;
7. Control terminates on Goal completion, failure budget, no progress, resource
   budget, or user interruption;
8. the complete CO/event graph survives restoration and can be inspected from
   both supported clients.

The first acceptance scenario is a failure-first Fibonacci task: the first
generated implementation must be rejected, the feedback must re-enter the
cycle, a revised Action must pass deterministic tests, and only then may Control
emit `GoalCompleted`.
