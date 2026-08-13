# GCAS-Core: GAIA's Minimal Cognitive Cycle

This document is the acceptance contract for migrating GAIA to [GCAS](../gcas.md).
It does not define a single recursive call or an LLM loop. It defines a minimal,
controlled feedback process in which no processor is the source of truth for the
entire system.

## Reference Scenario

Question: *"Is claim X from publication Y true?"*

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
| 9. Belief update | control + memory | a new Claim version; `CO_Superseded` or `ConflictDetected` | contradictory claims are never silently removed |
| 10. Termination | cognitive control | `GoalCompleted` or `ProcessTerminated` | the goal criterion is met, or the outcome is `INCONCLUSIVE`, `FAILED`, or `INSUFFICIENT_INFORMATION` |

## Execution Invariants

1. `publish(CO)` submits a candidate; it does not mean broadcast or execution.
2. The Workspace has bounded capacity; admission follows a selection policy.
3. An LLM output begins as `HYPOTHESIS` and `UNVERIFIED`.
4. A REPL result is an observation of execution, not automatically a fact about the world.
5. Every `Result` or `Failure` references the Action that caused it.
6. Control terminates a process from its budget, progress, and goal criterion—not only an LLM's declared confidence.

## Current Implementation Scope

`gaia cognitive-session` implements stages 5–7 in the minimal core:

```text
session-submit! → CandidateSubmitted
session-advance! → selective admission → WorkspaceBroadcast
session-record-result! / session-record-failure! → ActionCompleted / ActionFailed
```

The next steps are to attach this core to a server session, route sandbox/REPL work
behind `ActionRequested`, and then add memory, planning, and deliberative processors.
