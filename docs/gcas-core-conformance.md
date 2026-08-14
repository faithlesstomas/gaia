# GCAS-Core Conformance Gap Audit

This document evaluates GAIA against the eight minimum requirements in
[GCAS §11.2](../gcas.md#112-minimal-conformance-requirements-gcas-core). It is a
gap audit, not a declaration of conformance.

**Current conclusion:** GAIA implements a substantial GCAS substrate, including
a per-Goal process lifecycle, production processors attached to the Cognitive
Bus, explicit Workspace rounds, and bounded feedback replanning. It is not yet
operationally GCAS-Core conformant because goal-specific verification and the
corresponding Answer policy are not implemented.

Status meanings:

- **Implemented:** present in the production path with acceptance evidence.
- **Partial:** supporting contracts exist, but production behavior does not yet
  satisfy the complete requirement.

| GCAS-Core requirement | Status | Implemented substrate | Remaining conformance gap |
|---|---|---|---|
| Explicit COs, 3-axis metadata, provenance | Implemented | `gaia com` defines immutable COs with epistemic status, verification status, confidence, temporal validity, provenance, and relations. | Expand lifecycle validation as the ontology grows; this is not a current Core blocker. |
| Hypotheses distinct from beliefs | Implemented | LLM output begins as `HYPOTHESIS`/`UNVERIFIED`; execution success does not establish the user's original claim. | Keep accepted execution observations explicitly scoped so `BeliefUpdated` cannot be mistaken for goal verification. |
| Bounded Workspace with selective admission/broadcast | Implemented | Control records explicit Workspace rounds, selects one pending candidate by scheduling metadata, broadcasts it, and releases active focus while preserving the CO in State. | Improve scheduling policy with novelty, urgency, information gain, and goal-aware attention. |
| At least Generative and Deliberative processors | Implemented | Memory Retrieval, Generative, Planner, Execution, Deliberative, Answer, and Control processors subscribe through the Cognitive Bus. The orchestrator supplies asynchronous LLM, sandbox, and client adapters. | Planner currently maps one Hypothesis to at most one Action; richer planning belongs to the recurrent-cycle gap. |
| Memory separate from prompt history | Implemented at minimum, functionally limited | Structured CO memory is persisted separately and selected context is reconstructed without appending chat history. | Memory currently stores mainly Question/Goal COs and uses lexical overlap. Add evidence/claim consolidation, typed memory functions, and retrieval capable of preserving facts such as user-provided identity. |
| Recurrent cognitive cycle with progress and loop monitoring | Implemented at bounded minimum | Every `solve` has isolated budgets and exactly-once termination. Failed actions and conflicts become Reflection COs, which trigger a bounded revised Hypothesis → Plan → linked subgoal → Action pass; Control monitors transition, failure, stall, and replan limits. | Add richer strategy switching and goal-aware progress measures. |
| Separate execution with auditable Action/Result | Implemented | An admitted Action crosses an explicit sandbox boundary; Result/Failure links to it and receives a reproducibility observation. | Extend the policy gate beyond checking only the `action` type and add richer environment manifests after Core. |
| Explicit uncertainty, time, and failure | Implemented | COs represent confidence and temporal validity; failure and inconclusive terminal states are durable. | Make goal-level uncertainty and termination rationale visible in client-facing process views. |

## Production behavior observed in the audit

The current `solve` path:

1. creates Question and Goal COs with identical text;
2. collects pending candidates into explicit Control-managed Workspace rounds;
3. reacts to `GoalCreated` with Memory Retrieval and reconstructed context;
4. lets Generative invoke the LLM with empty chat history and, after failure or conflict, with reconstructed feedback context;
5. lets Planner create a `Plan`, a linked subgoal `Goal`, then an Action from each Hypothesis;
6. lets Execution and Deliberative processors produce Result/Failure, Evidence,
   and a bounded execution Claim;
7. routes ActionFailed and ConflictDetected through Reflection into bounded replanning;
8. lets the Answer Processor terminate as `INSUFFICIENT_INFORMATION`, `FAILED`,
   or `INCONCLUSIVE`.

The event trace drives a multi-processor recurrent production process, rather
than merely recording direct orchestrator calls. A successful sandbox call still
produces only a verified claim about execution, not proof that the Goal is met;
Planner therefore returns an explicit `INCONCLUSIVE` outcome pending an
independent goal verifier.

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
4. Result/Failure/Conflict events return to planning, and failure/conflict
   feedback can trigger a subsequent generation iteration;
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
