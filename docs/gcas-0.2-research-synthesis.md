# GCAS 0.2 — Research Synthesis and Decision Log

**Status:** Supporting, non-normative document

**Scope:** Consolidation of the earlier GCAS review with AGI-26 and adjacent research

**Normative specification:** [`../gcas.md`](../gcas.md)

## 1. Purpose

This note records why GCAS 0.2 differs from 0.1. The earlier review correctly identified the missing process model. The later research
review largely confirmed that diagnosis, but made several requirements sharper: verification must name its target; memory retrieval must
not silently become belief; successful execution must not stand in for task correctness; and architectural value must be demonstrated
against simpler baselines.

GCAS remains an architecture for reliable, persistent LLM-based and hybrid systems. It neither claims to implement AGI nor uses
consciousness as an explanatory or conformance requirement.

## 2. Consolidated Findings

| Earlier review | AGI-26 and adjacent research | GCAS 0.2 decision |
| :--- | :--- | :--- |
| GCAS needs a Cognitive Process and Event Model. | Executable world models and the Hypothesis Surface emphasize explicit, testable transitions. | Add the abstract machine, events, processor contracts, lifecycle, and a normative inquiry trace (§13). |
| Cognitive Objects, State, Events, and Processes are distinct abstractions. | Reproducible agent evaluation requires separating persistent state from transient execution. | Define durable transition records and duplicate-safe terminal semantics (§13.1–13.4). |
| Provenance, epistemic status, verification, and confidence must remain separate. | Truth-maintenance, PROV-O, and hallucination research expose the danger of treating a score or citation as truth. | Add verification targets, typed confidence, source lineage, and justification/invalidation graphs (§3, §13.6). |
| Derivation validity is not world truth. | Formal checking and executable evaluation cover bounded properties, not all grounding assumptions. | Define scoped assurance classes V0–V5 and prohibit status promotion beyond verified scope (§13.13). |
| Workspace is a dynamic process, not a buffer. | Global-workspace language alone does not establish an engineering benefit. | Specify observable bounded rounds and require comparisons and ablations (§13.5, §14.3). |
| Cognitive control must not become a central homunculus. | Common Model metacognition supports explicit self-state and functional control capabilities. | Specify functional processor roles and trace-grounded Reflection without requiring one executive (§13.3, §13.10). |
| Memory should reconstruct context rather than accumulate transcripts. | Long-context and memory-centric agent research shows position, distraction, staleness, and horizon effects. | Make retrieval epistemically neutral and require guarded merge, revalidation, and governed consolidation (§8, §13.9). |
| An LLM is a hypothesis generator, not an oracle. | Self-correction is unreliable without feedback; semantic uncertainty does not itself verify a claim. | Record generator/verifier dependencies and separate self-review from external checks (§7, §13.13). |
| Cognition and execution are separate. | Executable world models make proposed action, runtime result, and objective success independently testable. | Add a governed Action transaction and a distinct `GOAL_SATISFACTION` target (§9, §13.7–13.8). |
| J-space belongs behind NCSI, not at the architectural center. | Representation probes can be unstable, correlational, or unfaithful to causal computation. | Treat NCSI values as processor observations, never direct epistemic evidence (§7.3). |
| The specification needs a complete dry run. | Scientific-agent work benefits from explicit hypotheses, counterevidence, abstention, and reproducible traces. | Add the 16-stage normative scientific inquiry trace (§13.12). |
| Cost and bounded resources are part of cognitive control. | Resource-bounded induction and long-horizon evaluation make budget an algorithmic constraint. | Put budgets in machine and Goal state; require bounded non-progress handling (§13.1, §13.7, §13.11). |

## 3. Decisions That Were Rejected or Deliberately Deferred

* **Global Workspace = J-space:** rejected. A neural representation space may inform attention but is not the logical Workspace.
* **One scalar confidence for every object:** rejected. Metrics require declared semantics and calibration; heterogeneous evidence may be
  incommensurable.
* **`FORMALLY_VERIFIED` means true in the world:** rejected. It verifies a declared derivation or property under explicit assumptions.
* **A universal Central Executive:** rejected as a conformance requirement. Control may be centralized, distributed, or hybrid.
* **Guile, Hyperon, MeTTa, Guix, a particular LLM, or J-space in the standard:** deferred to reference implementations and profiles.
* **AGI or machine consciousness as the project objective:** out of scope. GCAS conformance is an architectural claim, not a claim of
  general intelligence or phenomenology.

## 4. Compatibility and Implementation Consequences

GCAS-Core remains the smaller architectural profile. GCAS-Process 0.2 is additive but intentionally stricter: existing implementations
must not advertise 0.2 process conformance merely because they have events, memory, tools, or multiple processors.

The GAIA implementation should be audited against these concrete deltas:

1. verification records need explicit target, scope, coverage, assumptions, and assurance class;
2. Cognitive Object content changes need immutable semantic versions and dependency invalidation;
3. source lineage needs to reveal shared ancestry between apparently independent evidence;
4. memory reconstruction needs a guarded merge policy that preserves fresh observations and constraints;
5. Goals need acceptance contracts and evidence coverage, not only completion flags;
6. Action success and Goal satisfaction need separate terminal records;
7. Workspace admission/scoring must be observable enough for deterministic tests and ablations;
8. Reflection must cite trace evidence and terminate or replan boundedly after non-progress;
9. evaluation must separate invariant tests, competence tests, and architectural comparisons.

This list is an implementation audit agenda, not a claim that every item is currently absent.

## 5. Falsifiable Research Program

The central empirical question is not whether GCAS resembles a cognitive theory. It is whether its mechanisms improve reliability under
controlled cost and latency. Each major mechanism should therefore be removable and compared with model-only, transcript accumulation,
plain RAG, and simpler memory baselines.

Priority hypotheses are:

* guarded merge reduces stale-memory errors without excessive abstention;
* typed verification and verifier independence reduce false acceptance;
* justification graphs improve contradiction handling and revision correctness;
* bounded Workspace competition improves task success per unit cost over direct routing;
* explicit progress and terminal semantics reduce looping and silent task abandonment;
* context reconstruction degrades more slowly with task horizon and evidence displacement than transcript accumulation.

A negative result should simplify GCAS. Cognitive-theory vocabulary is useful only when it yields an operational boundary, a measurable
prediction, or a reusable implementation contract.
