# GAIA MVP — Persistent Verified Assistant

## Product claim

The GAIA MVP is a local-first, persistent GCAS 0.3 assistant that can remember
verified facts and procedures across sessions, use selected memories to pursue
new Goals, preserve provenance and contradictions, act only through a governed
execution boundary, and return either verified completion or an explicit
non-success outcome.

The MVP is not defined by a chat UI or by the ability of an LLM to produce a
plausible response. Its defining property is durable cognitive continuity:
useful state survives inference calls, client reconnects, process termination,
and server restarts without replaying a conversation transcript as memory.

## Required invariants

Every MVP capability must preserve the GCAS-Core 0.2 regression gate and
additionally satisfy the applicable GCAS 0.3 requirements:

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
7. **Correctness, verification, and confidence remain distinct.** A verifier
   outcome may observe a declared correctness target; neither verification nor
   confidence silently substitutes for that observation.
8. **Uncertainty is typed and auditable.** Decision-relevant uncertainty names
   its target, calculus, scope, evidence, update method, and validity. Missing
   uncertainty remains explicit instead of being replaced by a fabricated
   scalar.
9. **Attention is not confidence.** Workspace admission may prioritize an
   uncertain candidate because of risk, conflict, surprise, or expected
   information gain. Admission and broadcast never increase evidential weight.

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
| Bayesian correctness trace | A narrow verifier-backed target records a declared prior, evidence, posterior, posterior prediction, later correctness outcome, and a separate calibration update without rewriting the original assessment. |
| Uncertainty-driven attention | A high-risk or high-information candidate can outrank a more confident routine candidate, while both retain their original epistemic and verification state. |
| Distribution shift | An assessment outside its calibration scope is marked out of domain and triggers a declared widen, revalidate, abstain, or escalate policy. |

The deterministic memory gates now cover user testimony across restart,
verified cross-session graph memory, transitive invalidation, contradiction
revision, auditable supersession, stale-memory rejection, and verified
procedural reuse in `tests/test-cognitive-memory.scm`,
`tests/test-cognitive-memory-graph.scm`, and
`tests/test-production-processors.scm`. Failure-first repair and safe abstention
remain covered by the production and evaluation gates. Bayesian correctness,
uncertainty-driven attention, distribution shift, metacognitive capability
revision, and repeated live-model readiness remain milestone requirements, not
claims of current completion.

## Current implementation-slice boundary

The first two MVP implementation slices deliver M1 and M2 over the transparent
local store: durable typed memory edges and roles, bounded traversal, lazy STI,
governed terminal consolidation, guarded retrieval, dependency invalidation,
auditable contradiction revision and supersession, and cross-session memory
tests. The public memory interface preserves the backend adapter boundary. The
slices also align the documentation and conformance language with GCAS 0.3.
They do **not** claim `GCAS-Core 0.3`,
`GCAS-Uncertainty 0.3`, or
`GCAS-Bayesian 0.3` conformance and does not yet implement an uncertainty
calculus.

The subsequent implementation is intentionally split into reviewable vertical
slices. Each slice must preserve the existing exactly-once, fail-closed,
provenance, restoration, and client-protocol gates.

## GCAS 0.3 implementation plan

### U0 — Vocabulary and compatibility boundary

- Add `UncertaintyAssessment`, `CalculusDeclaration`, `CalibrationRecord`, and
  `CorrectnessObserved` Cognitive Object contracts.
- Make the assessment target, correctness event, uncertainty type, calculus,
  scope, conditioning evidence, representation, provenance, temporal validity,
  and diagnostics machine-validatable.
- Label the existing scalar CO `confidence`, Workspace `uncertainty`, neural
  readout strength, and legacy `FINAL/CONFIDENCE` values as distinct legacy or
  scheduling signals; do not reinterpret historical values as probabilities.

**Acceptance:** invalid or semantically incomplete assessments fail closed;
persisted legacy sessions still restore without acquiring invented semantics.

### U1 — Persistent uncertainty graph and projection

- Store assessments and declarations in the ordinary immutable CO graph with
  typed links to targets, evidence, priors, updates, mappings, and outcomes.
- Build `U` as a deterministic, rebuildable projection over those COs and graph
  relations, never as a second source of epistemic truth.
- Propagate invalidation and supersession through uncertainty dependencies while
  retaining the original assessment and decision trace.

**Acceptance:** an assessment/update chain survives restart, can be rebuilt
from `O` and `J`, and reacts auditably to invalidated evidence without rewriting
history.

### U2 — First Bayesian vertical slice

- Implement the closed-form Beta–Bernoulli trace from GCAS §13.13 for one
  narrow verifier-backed correctness target.
- Record prior and posterior predictive checks, likelihood assumptions,
  sensitivity, outcome observation, Brier contribution, and calibration sample
  count. Approximate-inference diagnostics are required only when an
  approximate method is introduced.
- Keep the Bayesian implementation behind the additive `GCAS-Bayesian 0.3`
  profile; the core storage and interfaces remain calculus-neutral.

**Acceptance:** deterministic tests reproduce the specification values and
prove that posterior confidence neither changes verification status nor
retroactively changes observed correctness.

### U3 — Workspace and Control integration

- Replace the monotonic uncertainty penalty with an inspectable policy whose
  features include urgency, risk, conflict, out-of-domain state, expected
  information gain, and cost while keeping scheduling priority separate from
  epistemic quantities.
- Add Goal-scoped acceptance, abstention, escalation, and value-of-information
  rules; avoid a universal confidence threshold.
- Require processors either to propagate material uncertainty or to record why
  it is irrelevant to an output.

**Acceptance:** deterministic competition tests cover both routine confident
content and uncertain high-impact content; Workspace activity alone never
changes confidence, correctness, or verification.

### U4 — Calibration, shift, and conformance gate

- Accumulate forecast/outcome pairs against immutable original assessments and
  report sample counts, proper scores, calibration curves, sharpness or set
  size, coverage, and decision loss where applicable.
- Detect calibration-scope violations and exercise declared out-of-domain and
  distribution-shift responses.
- Add an end-to-end `GCAS-Uncertainty 0.3` gate and report Bayesian-profile
  conformance separately for the covered Beta–Bernoulli domain.

**Acceptance:** the gate covers restart, invalidation, abstention, shift, and
cross-calculus non-combinability without weakening the existing GCAS 0.2
regression floor.

## Delivery milestones

### M0 — Contract and regression floor

- Maintain this Definition of Done and its mapping in `ROADMAP.md`.
- Keep GCAS-Core conformance, the deterministic competence corpus, Rust CLI,
  and Emacs protocol tests green.
- Add every implemented MVP scenario to an offline deterministic gate.
- Treat U0–U4 above as the GCAS 0.3 migration path; no milestone may claim
  conformance from schema presence alone.

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
