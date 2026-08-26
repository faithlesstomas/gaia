# GAIA MVP — Persistent Verified Assistant

## Product claim

The GAIA MVP is a local-first, persistent GCAS assistant that can remember
verified facts and procedures across sessions, use selected memories to pursue
new Goals, preserve provenance and contradictions, act only through a governed
execution boundary, and return either verified completion or an explicit
non-success outcome.

The MVP is not defined by a chat UI or by the ability of an LLM to produce a
plausible response. Its defining property is durable cognitive continuity:
useful state survives inference calls, client reconnects, process termination,
and server restarts without replaying a conversation transcript as memory.

## Required invariants

Every MVP capability must preserve the GCAS-Core gate and additionally show:

1. **Memory is not transcript history.** The model receives a transient context
   reconstructed from the active Goal, Workspace, selected Cognitive Objects,
   and constraints.
2. **Graph identity is durable.** Cognitive Objects and typed justification,
   contradiction, invalidation, and supersession relations survive restart.
3. **Retrieval is epistemically neutral.** Retrieval never promotes an object;
   invalidated or expired Claims are ineligible as current facts.
4. **History is not erased.** Superseded and invalidated objects remain
   inspectable with the CO that caused the change.
5. **Completion is independently accepted.** Model output and successful
   execution remain insufficient for `GoalCompleted` without the declared
   verifier contract.
6. **Failure remains a valid result.** Unsupported, inconclusive, interrupted,
   and budget-exhausted processes terminate exactly once and never masquerade
   as completion.

## MVP acceptance scenarios

The MVP readiness gate must exercise these scenarios end to end:

| Scenario | Required evidence |
|---|---|
| User testimony | A stated preference survives restart as an `Observation` with `USER_TESTIMONY` role and remains unverified. |
| Verified cross-session memory | A verified Evidence/Claim chain survives restart, is retrieved for a new Goal, and appears in reconstructed context without transcript replay. |
| Contradiction and revision | Fresh opposing evidence creates an explicit Conflict; the prior Claim and its dependents become ineligible, remain auditable, and a successor can supersede them. |
| Procedural reuse | A verified successful procedure is consolidated with provenance and reused in a later related Goal. |
| Failure-first task repair | A failed Action produces Reflection, a distinct replacement Action, independent verification, and one terminal response. |
| Safe abstention | A task without sufficient evidence or verifier coverage ends as `INCONCLUSIVE` rather than false `COMPLETED`. |

The first implementation gate covers verified cross-session graph memory,
transitive invalidation, and supersession in
`tests/test-cognitive-memory-graph.scm`. The remaining scenarios are milestone
requirements, not claims of current completion.

## Delivery milestones

### M0 — Contract and regression floor

- Maintain this Definition of Done and its mapping in `ROADMAP.md`.
- Keep GCAS-Core conformance, the deterministic competence corpus, Rust CLI,
  and Emacs protocol tests green.
- Add every implemented MVP scenario to an offline deterministic gate.

### M1 — Cognitive Memory Graph v1

- Store COs as durable graph nodes with typed, queryable edges.
- Provide duplicate-safe link, traversal, dependency, invalidation, and
  supersession operations.
- Add explicit episodic, semantic, procedural, user-testimony, and
  metacognitive roles.
- Add basic STI/LTI activation and bounded goal-driven traversal.
- Preserve an adapter boundary so the storage implementation can evolve from
  the transparent local store to Goblins actors or another AtomSpace backend
  without changing GCAS semantics.

### M2 — Consolidation and guarded retrieval

- Attach a Consolidator to terminal process events.
- Record why an object is retained, its memory role, revalidation conditions,
  and the evidence behind any generalization.
- Propagate invalidation through justification dependencies.
- Select memory by Goal relevance, graph relations, time, provenance,
  contradiction state, and activation rather than lexical overlap alone.

### M3 — Capability and verifier registry

- Define reusable exact-value, structured-value, predicate/property,
  unit-test, artifact, environment-state, and human-approval verifier classes.
- Give each advertised capability an intent matcher, Goal contract, capability
  manifest, planner/action schema, verifier, deterministic fixture, and live
  evaluation case.
- Continue to fail closed for unknown task classes.

### M4 — Structured Action and repair

- Preflight syntax and capability policy before persistent mutation.
- Project typed initial, syntax-repair, runtime-repair, and verifier-repair
  contexts with remaining budgets.
- Require one complete, distinct replacement Action and detect non-progress.

### M5 — Longitudinal readiness gate

- Run repeated live-model evaluations for every advertised capability.
- Measure task success, correct abstention, false completion, terminal rate,
  first-pass and repair success, repeated Actions, calls, tokens, latency, and
  interruption latency.
- Add multi-session tests for retrieval, revision, procedural reuse, and stale
  memory rejection.

### M6 — Security and release

- Replace shell-prefix command checks with parsed/direct execution policy.
- Complete client UI support for scoped HITL permissions.
- Publish the exact supported capability matrix and readiness thresholds.

## Deferred beyond MVP

The MVP does not require J-space steering, a distributed AtomSpace, full
Hyperon integration, governed self-training, Lean/Z3 proving, voice, vision, or
desktop automation. These may extend the same graph, processor, Action, and
verification contracts after the persistent verified-assistant gate passes.
