# GCAS-Core: GAIA's Minimal Cognitive Cycle

This document is the acceptance contract for migrating GAIA to [GCAS](../gcas.md).
It does not define a single recursive call or an LLM loop. It defines a minimal,
controlled feedback process in which no processor is the source of truth for the
entire system.

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

`gaia gcas-showcase` implements all ten stages for the executable reference
scenario. `gaia cognitive-session` provides the reusable State, Workspace, Bus,
and Control coordination beneath it. Server sessions now own this coordinator,
and direct REPL requests are recorded as an explicit `Action` followed by
`ActionCompleted` or `ActionFailed`:

```text
session-submit! → CandidateSubmitted
session-advance! → selective admission → WorkspaceBroadcast
session-record-result! / session-record-failure! → ActionCompleted / ActionFailed
```

Run the executable deterministic showcase with:

```sh
make gcas-showcase
```

It demonstrates the confirmed, conflicting-evidence, and failed-execution
outcomes without an external model service. The automated showcase test verifies
the full event trace for all three outcomes.

The default server `solve` path now routes model output through
`HypothesisProposed` and an explicitly admitted `ActionRequested` before it can
reach the sandbox. The former recursive LLM–REPL loop is retained behind the
separate `investigate` command as an optional legacy Investigation Processor.
The next steps are a deliberative processor and structured memory/retrieval.
