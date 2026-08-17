# GCAS-Core: GAIA's Minimal Cognitive Cycle

This document is the acceptance contract for migrating GAIA to [GCAS](../gcas.md).
It does not define a single recursive call or an LLM loop. It defines a minimal,
controlled feedback process in which no processor is the source of truth for the
entire system.

**Status:** the production path satisfies this minimal operational contract.
The conformance gate exercises the same `solve` path used by the server and
clients, including failure-first replanning, restoration, Control termination,
and client inspection. The deterministic showcase remains a narrower scripted
contract demonstration. Unsupported task classes still terminate safely as
`INCONCLUSIVE` when no task-specific verifier is registered.

## Executable Reference Scenario

Question: *"Does the Guile expression `(+ 20 22)` evaluate to `42`?"*

This deterministic, reproducible claim is deliberately narrower than the future
publication-evaluation benchmark in GCAS 0.2. It exercises every transition of
the same cognitive process without requiring a network source or model service.

| Stage | Input / processor | State change and event | Transition condition |
|---|---|---|---|
| 1. Question | user | `Question` CO; `ObservationReceived` | a goal is created or clarification is requested |
| 2. Goal | planner / control | `Goal` CO; `GoalCreated` | the goal has completion criteria and a budget |
| 3. Retrieval | memory processor | memory or evidence CO; `MemoryRetrieved` | only goal-relevant context becomes a candidate |
| 4. Hypothesis | generative processor | `Hypothesis` with `LLM`, `HYPOTHESIS`, `UNVERIFIED`; `HypothesisProposed` | a hypothesis cannot update a belief without evidence |
| 5. Selection | workspace + control | `CandidateSubmitted`, then `WorkspaceBroadcast` | candidates compete on relevance, risk, uncertainty, and budget |
| 6. Action | planner + policy gate | `Action` CO; `ActionRequested` | only an explicitly permitted action reaches an executor |
| 7. Observation | REPL / sandbox | `Result` or `Failure` CO; `ActionCompleted` or `ActionFailed` | the outcome references its Action and a reproducibility record |
| 8. Evaluation | deliberative processor | `Evidence`, `Conflict`, derivation, or `Reflection` CO | a valid derivation is not automatically world truth |
| 9. Belief update | control + memory | a new Claim version; `BeliefUpdated` or `ConflictDetected` | contradictory claims are never silently removed |
| 10. Termination | cognitive control | `GoalCompleted` or `ProcessTerminated` | the goal criterion is met, or the outcome is `INCONCLUSIVE`, `FAILED`, or `INSUFFICIENT_INFORMATION` |

## Execution Invariants

1. `publish(CO)` submits a candidate; it does not mean broadcast or execution.
2. The Workspace has bounded capacity; admission follows a selection policy.
3. An LLM output begins as `HYPOTHESIS` and `UNVERIFIED`.
4. A REPL result is an observation of execution, not automatically a fact about the world.
5. Every `Result` or `Failure` references the Action that caused it.
6. Control terminates a process from its budget, progress, and goal criterion—not only an LLM's declared confidence.

Control primitives track transitions, observable progress, consecutive
non-progressing transitions, execution failures, and explicit user interruption.
They define `BUDGET_EXHAUSTED`, `NO_PROGRESS`, `FAILURE_BUDGET_EXHAUSTED`, and
`USER_INTERRUPTED`. Production creates a fresh Control/process lifecycle per
Goal, enforces exactly one durable terminal outcome, and bounds feedback-driven
replanning with transition, failure, stalled-transition, and replan budgets.
The same terminal boundary invokes the client completion callback exactly once;
Control-driven budget outcomes are rendered as terminal `final` responses just
like Answer-Processor outcomes.

## Workspace and Processor Contract

The current workspace is a bounded candidate queue, separate from Cognitive
State. A processor subscribes to semantic events and may return proposals; its
proposals are stored as COs and enter the workspace as `CandidateSubmitted`.
They are never broadcast or executed merely because a processor produced them.

Each proposal carries explicit scheduling metadata: `priority`, `relevance`,
`risk`, `cost`, and `uncertainty`. Cognitive Control uses a deterministic,
inspectable baseline policy: it prefers higher priority and relevance while
penalizing risk, cost, and uncertainty. It preserves submission order for equal
scores. Capacity prevents a further admission until an active CO is released.

This is a deliberately small policy, not an assertion that these weights are a
final model of attention. It provides a tested replacement point for future
goal-, budget-, and safety-aware scheduling.

## Current Implementation Scope

`gaia gcas-showcase` scripts all ten stages for the executable reference
scenario. It verifies the CO/event contracts but does not prove that production
processors are reactively coordinated. `gaia cognitive-session` provides the
reusable State, Workspace, Bus, and Control substrate. Server sessions own this
substrate, and direct REPL requests are recorded as an explicit `Action` followed
by `ActionCompleted` or `ActionFailed`:

```text
session-submit! → CandidateSubmitted
session-run-workspace-round! → competition → selective admission → WorkspaceBroadcast → release focus
session-record-result! / session-record-failure! → ActionCompleted / ActionFailed
```

Each server session durably records its CO graph and chronological event log in
`sessions/<session-id>.gcas-state.scm`. An execution outcome also creates a
reproducibility observation linked to its Action and Result/Failure, containing
the submitted payload, outcome, output, runtime label, and timestamp. `/clear`
creates a fresh durable cognitive boundary; it does not silently restore the
previous graph.

Run the executable deterministic showcase with:

```sh
make gcas-showcase
```

It demonstrates the confirmed, conflicting-evidence, and failed-execution
outcomes without an external model service. The automated showcase test verifies
the full event trace for all three outcomes.

The default server `solve` path routes model output through
`HypothesisProposed` and an admitted `ActionRequested` before it reaches the
sandbox. A successful action becomes `Result`, `Evidence`, and a verified claim
about the observed execution. The independent Goal Verifier receives that claim
and may create a Claim satisfying the Goal. Without a task-specific verifier,
the safe default verdict is `INCONCLUSIVE`.

This path is assembled from Memory Retrieval, Generative, Planner, Execution,
Deliberative, Answer, and Control processors attached to the Cognitive Bus. Each
`solve` owns a separate Goal process, completion criteria, Control budgets, and
exactly one terminal transition. Control collects proposal batches into explicit
Workspace rounds, selects one candidate, broadcasts it, then releases that
focus while preserving its durable CO record.

Planner turns each Hypothesis into a `Plan`, a linked subgoal represented as a
`Goal` CO, and then an `Action`. An
`ActionFailed` or `ConflictDetected` creates a `Reflection` candidate; when it
is selected, Generative reconstructs context containing that feedback and
proposes a revised Hypothesis, Plan, and Action. A successful Result similarly
returns through Evidence and a bounded execution Claim to the Goal Verifier.
Rejected evidence becomes `ConflictDetected` and re-enters planning; an
inconclusive verdict ends without presenting model output as the answer.
The legacy recursive LLM–REPL loop remains behind `investigate` and is not the
GCAS cycle.

`gaia deliberative-processor` now provides the first deliberative contract:
an execution observation first becomes `Evidence`, then an independently
supplied verifier may create an accepted, verified `Claim`. A failed verifier
creates `ConflictDetected` and never an accepted claim. It is intentionally
separate from the LLM proposal path.

`gaia cognitive-memory` persists structured COs locally, retrieves only memory
relevant to the current goal, and reconstructs an LLM context from the current
goal, admitted workspace, selected memory, and active constraints. Server
`solve` sends this reconstruction with empty chat history; the transcript stays
an episodic audit record rather than becoming prompt memory. Accepted user
testimony and verified Result/Evidence/Claim chains are consolidated and can be
retrieved across turns; their provenance remains explicit.

## Production Acceptance Criteria

The production cycle is complete only when:

1. each `solve` creates a Goal with explicit completion criteria and its own
   process budget;
2. Planner, Memory Retrieval, Generative, Execution, Deliberative, and Answer
   processors subscribe through the Cognitive Bus;
3. Workspace admission selects among concurrently pending proposals;
4. Result, Failure, Conflict, and Reflection may cause another cycle iteration;
5. a goal-specific verifier, not REPL success, authorizes `GoalCompleted`;
6. the Answer Processor renders accepted knowledge and terminal rationale rather
   than exposing raw LLM output as the system answer;
7. the failure-first Fibonacci vertical test and restoration/interruption tests
   pass through the same production path used by CLI and Emacs;
8. three failed Actions produce one `FAILURE_BUDGET_EXHAUSTED` terminal event,
   one completion callback, and a terminal protocol response instead of leaving
   a client waiting.

Run the production conformance gate with:

```sh
make gcas-conformance
```

For a faster, model-free check of recurrent outcomes, repair paths, budgets,
interrupts, and terminal-delivery invariants, run `make gcas-eval`. Its scope
and metrics are documented in
[gcas-evaluation.md](gcas-evaluation.md).

The reference capability deliberately proves repair, not breadth: the first
Fibonacci result is rejected, its Conflict becomes replanning feedback, and only
the corrected result can produce `GoalCompleted`.
