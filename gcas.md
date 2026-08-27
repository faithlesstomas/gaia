# GCAS — General Cognitive Architecture Specification

## GCAS 0.3 — Cognitive Process, Operational Semantics & Uncertainty Framework (Draft)

**Status:** Draft / Specification Proposal
**Version:** 0.3
**Scope:** Language- and implementation-independent cognitive architecture for persistent, hybrid neuro-symbolic intelligent systems.

---

## 0. Abstract

GCAS defines an abstract, implementation-independent architecture and operational model for persistent artificial cognitive systems capable of reasoning,
remembering, learning, planning, acting, verifying information, and interacting with external environments over extended periods of time.

GCAS is motivated by structural limitations of contemporary LLM-centric assistants, including:

* hallucination and unverified generation,
* context degradation and context rot,
* unreliable long-horizon reasoning and planning,
* lack of persistent identity, memory, and epistemic state,
* inability to distinguish knowledge from generated hypotheses,
* weak provenance tracking and unresolvable sources,
* poor computational reproducibility,
* unreliable self-correction and cycling,
* dependence on finite prompt context,
* and conflation of language generation with knowledge, reasoning, memory, and executive control.

GCAS treats a Large Language Model (LLM) not as the cognitive system itself, but as a specialized subsystem for **Generative Cognition**
participating within a broader cognitive architecture.

The architecture synthesizes core insights from:
* Global Workspace Theory (GWT),
* Dual-Process theories of cognition (Generative / Deliberative),
* Neuro-symbolic AI and formal logic,
* Cognitive architectures (ACT-R, SOAR, LIDA),
* Active, reconstructive, temporal, and episodic memory systems,
* Metacognition and self-monitoring,
* Scientific reasoning and hypothesis testing,
* Persistent computational environments (REPLs, operating systems),
* Event-driven reactive systems,
* and Reproducible computation.

GCAS specifies cognitive objects, interfaces, state transitions, information flows, invariants, and behavioral requirements rather than programming languages,
storage engines, neural architectures, or proprietary frameworks. Version 0.3 extends the operational semantics of GCAS 0.2 with a normative
uncertainty framework: Bayesian belief update and prediction, typed sources of uncertainty, calibration, uncertainty-aware decisions, and an
explicit separation between correctness, verification, and confidence.

---

# 1. Design Goals & Non-Goals

## 1.1 Design Goals

Systems conforming to GCAS SHOULD pursue the following design goals:

* **G1. Epistemic Reliability:** Explicitly distinguish between what is known, remembered, inferred, assumed, predicted, hypothesized,
  and unknown using a multi-axis epistemic model. Generation MUST NOT automatically constitute accepted knowledge.
* **G2. Persistent Cognition:** Maintain cognitive continuity across individual prompts, inference calls, processes, sessions, and system restarts.
* **G3. Bounded Active Context:** Restrict active working context to bounded working memory rather than attempting to maintain all historical state inside an LLM prompt.
* **G4. Context Reconstruction:** Dynamically assemble relevant context based on current goals, workspace state, and memory retrieval.
* **G5. Hybrid Neuro-Symbolic Reasoning:** Integrate heterogeneous reasoning mechanisms (generative, deliberative, symbolic, probabilistic, algorithmic, formal verification).
* **G6. Reproducibility:** Record execution and derivation state sufficiently to enable exact or probabilistic reproduction.
* **G7. Provenance Tracking:** Maintain audit trails identifying the origin, derivation, and supporting evidence for persistent claims.
* **G8. Explicit Uncertainty & Time:** Represent, update, propagate, calibrate, and communicate typed uncertainty, confidence, contradiction,
  and temporal validity intervals explicitly.
* **G9. Metacognition:** Support reasoning about system performance, resource usage, progress, and failure modes.
* **G10. Evolvability:** Enable modular replacement and upgrade of cognitive processors without architecture redesign.

## 1.2 Non-Goals

GCAS does NOT specify:
* A programming language or specific compiler,
* A specific LLM architecture or neural model weights,
* A specific database or storage engine,
* A specific formal logic system,
* An operating system or container runtime,
* A definition, test, or certification of artificial general intelligence,
* Consciousness, subjective experience, or qualia,
* A claim that compliant systems are generally intelligent or sentient.

Global Workspace Theory and cognitive science concepts serve strictly as architectural inspirations for information routing, coordination, and memory management.

---

# 2. Core Invariants & Fundamental Principles

## 2.1 Central Architectural Invariant

> **No individual cognitive processor constitutes the cognitive system.**

Cognition emerges strictly from the controlled, recurrent interaction of specialized processors through explicit cognitive state,
selective global workspace broadcast, memory, reasoning, action, and metacognitive feedback.

Consequently:
```
LLM ≠ Cognition
Memory ≠ Cognition
Workspace ≠ Cognition
Executive Control ≠ Cognition
Symbolic Reasoner ≠ Cognition
```
The cognitive system IS the recurrent process connecting them.

## 2.2 Derivation Validity vs. World Truth

GCAS enforces a strict distinction between formal logical validity and empirical truth:
* **Derivation Validity:** Proving that a conclusion $B$ logically follows from premises $A$ ($A \to B$) within a formal logic system.
* **World Truth:** Confirming that premises $A$ and conclusion $B$ correspond to actual facts in the external environment.

Formal derivation establishes *derivation validity*, NOT automatic *world truth*. World truth requires factual verification of premises.

## 2.3 Proposal ≠ Deployment

For system modification, governance, and action execution, GCAS enforces:
> **Proposal ≠ Deployment**

Proposing a hypothesis, plan, code edit, or self-modification DOES NOT grant authorization for execution or integration into persistent state without passing
through explicit validation, verification, and policy approval gates.

## 2.4 Separation of Cognitive Functions

GCAS enforces strict functional separation between:
* **Generation** (hypothesis proposal),
* **Knowledge** (verified, structured assertions),
* **Reasoning** (formal, symbolic, or logical derivation),
* **Memory** (episodic, semantic, procedural storage),
* **Action** (external/internal environment modification).

No single subsystem is assumed capable of reliably fulfilling all five roles.

## 2.5 Separation of Cognition and Representation

GCAS specifies cognitive semantics, not physical wire or memory formats.

For example, a proposition `Goal("verify hypothesis H")` MAY internally be represented as an S-expression, a MeTTa atom, a Rust struct, a Protobuf message,
a database record, or a tensor coordinate, provided GCAS semantics are strictly preserved.

## 2.6 Core Cognitive Abstractions

GCAS organizes cognitive computation into four primary abstractions:

```text
                COGNITIVE OBJECT
                       │
                 exists in
                       │
                       ▼
                COGNITIVE STATE
                       │
                 changes through
                       │
                       ▼
                COGNITIVE EVENT
                       │
                  triggers
                       │
                       ▼
                COGNITIVE PROCESS
                       │
                       ▼
                new STATE / OBJECTS
```

* **Cognitive Object (CO):** Semantic payload and unit of information.
* **Cognitive State:** The active graph of COs, beliefs, workspace elements, and active goals.
* **Cognitive Event:** State-change notifications distributed via the Cognitive Bus.
* **Cognitive Process:** Operational transitions transforming Cognitive State in response to Cognitive Events.

## 2.7 Correctness, Verification & Confidence Are Distinct

For any output, Claim, prediction, Plan, or Action outcome $y$, GCAS requires a declared **correctness target** $C_y$: the property and scope
against which $y$ would be judged correct. Correctness is a property of $y$ relative to that target. It may be true, false, partially satisfied
under a declared scoring rule, or presently unknown.

**Verification** is an evidence-producing process that tests a declared target with bounded scope and coverage. **Confidence** is an epistemic
quantity: the system's uncertainty-aware degree of belief that the correctness target is satisfied, conditional on stated evidence, assumptions,
model, scope, and time. For a binary target, a probabilistic confidence MAY be expressed as:

$$
q_y = P(C_y = 1 \mid E, M, S, t).
$$

Therefore:

```text
correctness != confidence
verification != correctness
confidence != verification status
```

A correct result MAY have low confidence, and an incorrect result MAY have high confidence. High confidence MUST NOT promote a Claim to
`VERIFIED` or `ACCEPTED`; only evidence evaluated under the applicable verification and acceptance contracts can do so. The unqualified word
"accuracy" SHOULD be reserved for empirical performance over evaluated cases, not used as a synonym for confidence on one unevaluated case.

## 2.8 Design Maxim

A compliant system MUST make the following distinctions explicit at every level:
```
what the system generated
what the system believes
what the system observed
what the system can prove
what the system can reproduce
what the system believes to be valid at time T
how uncertain the system is, about which target, and why
what the system does not know
```

---

# 3. Cognitive Object Model (COM)

Information within GCAS is encapsulated in **Cognitive Objects (COs)**. A Cognitive Object represents an identifiable, typed unit participating in cognition.

## 3.1 Object Schema & Metadata

Every Cognitive Object SHOULD carry metadata including:
* **Identity:** Unique identifier (UUID, content hash, or URI).
* **Type:** Categorical type within the COM taxonomy.
* **Content:** Semantic payload.
* **Provenance:** Source or origin tag (`USER`, `SENSOR`, `LLM`, `MEMORY`, `EXECUTION`, `EXTERNAL_SOURCE`, `SYMBOLIC_INFERENCE`, `FORMAL_PROOF`).
* **Epistemic Status:** Current epistemic state (`UNKNOWN`, `HYPOTHESIS`, `ASSUMPTION`, `BELIEF`, `ACCEPTED`, `REFUTED`, `DISPUTED`).
* **Verification Status:** Level of validation (`UNVERIFIED`, `PARTIALLY_VERIFIED`, `VERIFIED`, `FORMALLY_VERIFIED`).
* **Verification Target:** The property actually checked (`DERIVATION_VALIDITY`, `EXECUTION_RESULT`, `SOURCE_ATTESTATION`,
  `EMPIRICAL_CLAIM`, `GOAL_SATISFACTION`, or a domain-specific extension).
* **Uncertainty Assessments:** References to versioned `UncertaintyAssessment` COs. Each assessment identifies its target quantity, semantics,
  conditioning evidence, representation, scope, calibration domain, and update method. A scalar confidence $[0.0, 1.0]$ MAY be used only for a
  declared event such as correctness of a binary target; heterogeneous reliability measures MUST NOT be collapsed into one unlabeled score.
* **Timestamp & Temporal Validity:** Creation time and temporal validity interval (`valid_from`, `valid_to`, `invalidated_by`).
* **Relations / Dependencies:** Graph links to supporting, parent, or contradicting COs.
* **Scope:** The entities, environment, task, time, and assumptions within which the content is asserted to hold.
* **Lifecycle State:** Operational state independent of epistemic status (`CREATED`, `PROPOSED`, `ADMITTED`, `ACTIVE`, `SUPERSEDED`,
  `RETRACTED`, `ARCHIVED`).

## 3.2 Multi-Axis Epistemic Model

To prevent semantic conflation, GCAS requires three independent primary axes and additional scoped qualifiers:

```text
                          ┌───────────────────────────┐
                          │     Cognitive Object      │
                          └─────────────┬─────────────┘
                                        │
           ┌────────────────────────────┼────────────────────────────┐
           ▼                            ▼                            ▼
  [ Epistemic Status ]            [ Provenance ]           [ Verification Status ]
  • UNKNOWN                       • USER                   • UNVERIFIED
  • HYPOTHESIS                    • SENSOR                 • PARTIALLY_VERIFIED
  • ASSUMPTION                    • LLM                    • VERIFIED
  • BELIEF                        • MEMORY                 • FORMALLY_VERIFIED
  • ACCEPTED                      • EXECUTION
  • REFUTED                       • EXTERNAL_SOURCE
  • DISPUTED                      • SYMBOLIC_INFERENCE
                                  • FORMAL_PROOF
```

### Concrete Object Structure Example
By keeping these axes orthogonal, a Cognitive Object can express multi-dimensional state without ambiguity:

```text
Claim #402: "Compound X inhibits Target Y"

provenance:          EXTERNAL_SOURCE ("paper-doi-10.1038/s41586")
epistemic-status:    BELIEF
verification-status: PARTIALLY_VERIFIED
verification-target: EMPIRICAL_CLAIM
uncertainty-assessments:
  - {target: correctness(EMPIRICAL_CLAIM), representation: bernoulli(p=0.82),
     calibration-support: {n: 220, empirical-95%-interval: [0.76, 0.87]}, calibration-domain: assay-A4-v2,
     conditioned-on: [evidence-91, evidence-103], method: bayes-model-7}
temporal-validity:   [2026-01-15, INF]
scope:               {compound-batch: X-17, assay: A4}
```

### Epistemic Classification Rules
1. **Observation ≠ Fact:** Information received from sensors or user input is an `Observation` with provenance `SENSOR` or `USER`.
   It MUST NOT automatically be classified as `VERIFIED` or `ACCEPTED` without verification (e.g. faulty sensor or unverified user claim).
2. **LLM Output = Hypothesis:** Content generated by neural models MUST carry provenance `LLM` and initial epistemic status `HYPOTHESIS`.
   When an LLM copies, transforms, or summarizes observations, each resulting Claim MUST additionally retain derivation links to those observations.
3. **Fact Definition:** A **Fact** is defined strictly as a scoped Claim with epistemic status `ACCEPTED`, a declared verification target,
   and verification evidence sufficient under an explicit acceptance policy. `FORMALLY_VERIFIED` with target `DERIVATION_VALIDITY` proves
   only the derivation and MUST NOT by itself establish an `EMPIRICAL_CLAIM` as world truth.
4. **Selection ≠ Verification:** Workspace admission, repetition, retrieval frequency, model agreement, or high confidence MUST NOT by
   themselves change a Claim to `VERIFIED` or `ACCEPTED`.

## 3.3 Temporal Epistemic Model

Epistemic validity MUST be bounded in time. GCAS represents temporal epistemic state as:
```text
Belief B was accepted at t1
Evidence E observed at t2 invalidated B
B is valid in temporal interval [t1, t2]
```
Systems MUST NOT treat historical beliefs as timeless truths.

## 3.4 Cognitive Object Taxonomy

1. **Observation:** Information received directly from environment, sensors, user input, or execution runtimes. Observation does not imply interpretation or truth.
2. **Claim:** A proposition whose truth value requires evaluation.
3. **Belief:** A Claim currently accepted by the system with explicit uncertainty assessments and provenance. Contradictory beliefs MAY temporarily coexist.
4. **Hypothesis:** Candidate explanation or solution requiring verification.
5. **Evidence:** Information supporting or opposing a Claim, Hypothesis, or Belief. Must carry provenance.
6. **Goal:** Desired state or unresolved query. May contain subgoals and completion criteria.
7. **Plan:** Structured sequence of proposed Actions and verification steps to satisfy a Goal.
8. **Action:** Intended interaction with external or internal execution environments.
9. **Result:** Output returned from an executed Action or tool call.
10. **Question:** Unresolved information need directed to memory, reasoners, LLMs, tools, or users.
11. **Conflict:** Explicit representation of mutually incompatible Cognitive Objects. MUST NOT be resolved by silent deletion.
12. **Reflection:** Metacognitive assessment of a cognitive process, progress, or resource state.
13. **Rule / Procedure:** Reusable strategy or operational guidance stored in procedural memory.
14. **Uncertainty Assessment:** A versioned, scoped representation of uncertainty about a Claim, prediction, model, observation, process,
    Action outcome, or correctness target. It is evidence-conditioned metadata, not a truth label.

## 3.5 Cognitive Object Identity and Versioning

Cognitive Objects SHOULD be immutable semantic records. A substantive change of content, scope, epistemic status, verification status,
temporal validity, or dependencies SHOULD create a new version linked by `supersedes`, `revises`, or `invalidates` rather than silently
rewriting history. Implementations MAY use mutable physical records if they preserve an equivalent auditable version history.

Content identity and assertion identity MUST remain distinguishable. Two processors MAY assert semantically equivalent content with
different provenance, scope, or evidence; deduplication MUST NOT erase these distinctions.

## 3.6 Evidence and Justification Graph

Persistent epistemic Claims MUST participate in an explicit justification graph. Typed edges SHOULD include:

* `supports(Evidence, Claim)`,
* `opposes(Evidence, Claim)`,
* `derived-from(Claim, Premise-or-Observation)`,
* `assumes(Claim, Assumption)`,
* `verified-by(Claim, Verification)`,
* `quantified-by(Target, UncertaintyAssessment)`,
* `conditioned-on(UncertaintyAssessment, Evidence-or-Assumption)`,
* `updates(NewAssessment, PriorAssessment)`,
* `contradicts(Claim, Claim)`,
* `supersedes(New, Old)`,
* `invalidates(Evidence, Claim)`.

A Claim MUST NOT gain support merely because multiple retrieved objects repeat it. Systems SHOULD track source lineage and common
ancestry so that copied or mutually dependent sources are not treated as independent evidence. Invalidating a premise MUST make every
dependent Claim discoverable for re-evaluation; GCAS does not require one particular truth-maintenance algorithm.

## 3.7 Uncertainty Framework

Uncertainty in GCAS is a persistent, compositional part of Cognitive State. It is not merely a verbal hedge, token probability, raw neural
signal, or confidence number attached at rendering time. An `UncertaintyAssessment` is a versioned Cognitive Object in `O`, not a mutable
field whose history can be overwritten. Every assessment used in persistent belief, Workspace manipulation, Goal acceptance, Action selection,
or user-facing confidence MUST satisfy the following minimum schema:

| Field | Requirement |
| :--- | :--- |
| `assessment_id` | Stable identity for this immutable assessment version. |
| `target_ref` and `quantity` | Cognitive Object or correctness target assessed, and the exact uncertain quantity. |
| `calculus_id` and `calculus_version` | Declared representation and combination semantics, such as `bayesian-probability`, `credal-set`, `subjective-logic`, `conformal-set`, or `formal-bound`. |
| `value` and `outcome_space` | Distribution, samples, parameters, interval, set, masses, bounds, or another representation sufficient to interpret the assessment. |
| `semantics` and `units` | Meaning of the value, including whether it is belief, frequency, coverage, possibility, evidence mass, numerical error, or another quantity. |
| `uncertainty_sources` | One or more typed sources from §3.7.1, or an explicit reason why decomposition is not available. |
| `conditioned_on` and `assumptions` | Evidence, observations, priors, model assumptions, independence assumptions, and policy inputs on which the value depends. |
| `lineage` and `dependence` | Source ancestry and known shared failure modes needed to prevent double-counting. |
| `method` and `diagnostics` | Update, inference, estimation, or bound-construction method plus relevant budget, convergence, fit, coverage, or approximation diagnostics. |
| `previous_assessment_refs` | Assessments updated, superseded, compared, fused, or converted; empty only for an explicitly initial assessment. |
| `calibration_ref` | Applicable calibration record and domain, or `not-applicable`, `not-evaluated`, or `out-of-domain` with a reason. |
| `scope` and `validity` | Population, environment, model and policy versions, temporal interval, and other limits within which the assessment may be used. |
| `producer` and `created_at` | Responsible processor or policy and logical or wall-clock creation time. |

The schema MAY be physically embedded in a target CO, but its identity, version history, and relations MUST remain observable as if it were
a separate CO. Missing information MUST be represented as missing or unknown; implementations MUST NOT manufacture a precise value merely
to populate the schema. An assessment with unresolved semantics or invalid diagnostics MUST NOT participate in numeric comparison or an
automatic decision as though it were valid.

### 3.7.1 Typed Sources of Uncertainty

Implementations MUST distinguish sources when they require different updates or interventions:

* **Aleatoric / observational:** irreducible variability, measurement noise, ambiguous observations, or stochastic outcomes;
* **Parametric epistemic:** uncertainty about model parameters due to limited or unrepresentative evidence;
* **Structural epistemic:** uncertainty about model class, causal structure, hypotheses, assumptions, or ontology;
* **Distributional:** uncertainty that the current case is outside the data or calibration domain, including temporal drift;
* **Computational:** error or variance introduced by finite search, sampling, numerical approximation, truncation, or an unfinished computation;
* **Outcome / decision:** uncertainty about consequences of Actions after predictive and environment uncertainty have been propagated.

These types MAY be represented jointly, but MUST remain recoverable when they imply different actions. For example, more observations may
reduce epistemic uncertainty but not irreducible outcome noise; more computation may reduce approximation error but not missing evidence.

### 3.7.2 Reference Bayesian Semantics and Workflow

Bayesian probability is the reference semantics for quantified degrees of belief, learning, and prediction in GCAS 0.3. It makes the
prior-to-posterior transition precise without requiring every GCAS-Core uncertainty quantity to be Bayesian. An implementation that labels
an assessment or update as Bayesian MUST implement the semantics in this section for its declared scope.

Given model or hypothesis $m$, latent parameters $\theta$, existing evidence $D$, and new evidence $e$, a Bayesian update records the
versioned transition:

$$
p(\theta, m \mid D, e) =
\frac{p(e \mid \theta, m, D)\,p(\theta, m \mid D)}
     {p(e \mid D)},
\qquad
p(e \mid D) = \sum_m \int p(e \mid \theta, m, D)\,p(\theta, m \mid D)\,d\theta.
$$

The previous posterior becomes the next prior only within compatible scope and assumptions. Priors MUST be explicit, versioned, and
inspectable; likelihoods MUST identify the observation model and source-dependence assumptions. Evidence with common ancestry or correlated
failure modes MUST NOT be multiplied as conditionally independent without justification.

Before conditioning on observations, the workflow SHOULD evaluate the implications of the model and prior through prior predictive simulation
or an equivalent analytic check where material and computationally feasible:

$$
p(y^{rep} \mid M) = \sum_m \int p(y^{rep} \mid \theta,m)\,p(\theta,m \mid M)\,d\theta.
$$

Implausible, impossible, or excessively concentrated prior predictions MUST trigger prior revision, model revision, an explicit waiver with
scope and rationale, or an `INCONCLUSIVE` outcome. Data MUST NOT be used both to tune a prior and to claim an independent prior-predictive
check unless that reuse is modelled and disclosed.

Predictions MUST propagate material parameter and model uncertainty through the posterior predictive distribution rather than silently use
only a point estimate:

$$
p(y_* \mid x_*, D) = \sum_m \int p(y_* \mid x_*, \theta, m)\,p(\theta, m \mid D)\,d\theta.
$$

Exact inference is not required. Approximate inference (including variational inference, MCMC, ensembles, Laplace methods, probabilistic
programming, or domain-specific approximations) MUST declare its method, resource budget, convergence or fit diagnostics where available,
and any known approximation uncertainty. A failure to compute a reliable posterior is itself a computational uncertainty outcome and MUST
NOT be rendered as sharp confidence.

After inference, posterior predictive checks SHOULD compare replicated data or outcomes with observations using discrepancies relevant to the
declared correctness and decision targets. A serious mismatch MUST create a model-criticism or distributional-uncertainty record and trigger
at least one declared response: expand or replace the model class, revise assumptions, use robust or imprecise bounds, collect discriminating
evidence, restrict scope, abstain, or escalate. Passing a finite set of checks does not prove the model correct.

Material Bayesian decisions SHOULD include sensitivity analysis over plausible priors, likelihoods, dependence assumptions, model classes,
and inference approximations. If the decision changes materially, the affected structural or computational uncertainty MUST be retained in
the assessment and propagated. Selecting one best model MUST NOT silently discard model uncertainty; model averaging, robust bounds, or an
explicit approximation and information-loss record is required when that uncertainty is decision-relevant.

### 3.7.3 Calculus Declaration and Interoperability

GCAS-Core is uncertainty-calculus pluralist. Bayesian distributions, imprecise probabilities or credal sets, intervals, possibility measures,
Dempster-Shafer masses, Subjective Logic opinions, conformal prediction sets, formal proof bounds, and paraconsistent states MAY coexist when
their targets and semantics are appropriate.

Each `calculus_id` MUST resolve to a versioned declaration specifying:

* the value domain and interpretation;
* supported update, conditioning, marginalisation, propagation, fusion, and decision operations;
* required independence, exchangeability, closure, or other assumptions;
* validation and diagnostic obligations;
* compatible quantity and calculus versions;
* unsupported operations and known information loss.

Two assessments MUST NOT be numerically compared, fused, averaged, conditioned, or substituted merely because their values share a range such
as `[0,1]`. A cross-calculus transformation MUST create a new `UncertaintyAssessment` linked to its inputs and to a versioned mapping record
that states assumptions, validation domain, information loss, and whether the result preserves belief, coverage, bounds, or only a decision
ordering. A failed or unavailable mapping MUST preserve the separate assessments and may produce `INCONCLUSIVE` or request deliberation.

Logical contradiction is not itself probabilistic uncertainty. Truth-maintenance or paraconsistent mechanisms SHOULD preserve incompatible
Claims and their assumptions; a probabilistic or evidential assessment MAY be attached to each Claim, but MUST NOT erase the `Conflict` CO.

### 3.7.4 Calibration, Sharpness, and Empirical Correctness

Confidence is **calibrated** over an evaluation population when cases assigned probability $p$ satisfy the declared correctness target at an
empirical rate near $p$. Calibration is always conditional on target, population, model and policy version, time period, and distributional
scope. It is not a timeless property of a processor.

Systems that expose confidence SHOULD evaluate it on held-out or forward-in-time outcomes using proper scoring rules such as log loss or the
Brier score, calibration curves, interval coverage, and risk-coverage/selective-prediction metrics. Calibration error summaries MAY supplement
but MUST NOT replace the underlying curves and sample counts. Evaluation data MUST remain separate from the evidence used to produce the
assessed posterior unless the evaluation protocol explicitly models that reuse.

Forecast quality MUST NOT be claimed from calibration alone. Evaluation SHOULD report sharpness or concentration subject to calibration:
among assessments with valid calibration, narrower prediction intervals, smaller prediction sets, or more informative distributions are
preferred only when proper scoring rules and realised decision loss support them. A constant base-rate forecast may be calibrated but
uninformative. Conversely, sharp but miscalibrated assessments are unsafe.

When a correctness target later becomes observable, the system SHOULD create a `CorrectnessObserved` Verification or Result linked to the
original assessment, then update a separate calibration record. The later observation evaluates the earlier confidence; it MUST NOT rewrite
what the system knew or believed at the earlier time.

Observed distribution shift, material model change, or insufficient evaluation support MUST invalidate, widen, or qualify the applicable
calibration Claim. When an input is outside the calibration scope, the assessment MUST be marked `out-of-domain` unless a declared shift-aware
method supports transfer. The decision policy MUST then apply a recorded response appropriate to risk: use wider or robust bounds, obtain new
evidence, recalibrate, abstain, escalate, or restrict the Claim. Distribution-free or conformal coverage MUST NOT be described as invariant to
arbitrary shift; its exchangeability or other coverage assumptions remain part of scope.

Verbalized model confidence, token likelihood, entropy, verifier score, source reliability, evidential support, and posterior probability of
correctness are distinct quantities. A mapping between them MAY be learned, but MUST be validated for the declared domain.

### 3.7.5 Uncertainty-Aware Decision Semantics

Decisions MUST use predictive uncertainty together with consequences, not confidence alone. Where utilities and probabilities are available,
an Action policy SHOULD evaluate posterior expected utility and declared risk constraints:

$$
a^* \in \arg\max_a\; \mathbb{E}_{p(o \mid a,D)}[U(o,a)]
$$

subject to applicable safety, authorization, and tail-risk constraints. Acceptance, abstention, escalation, evidence acquisition, and Action
thresholds MUST be scoped to the cost of error and the Goal contract; a universal confidence threshold is non-conforming. The Controller
SHOULD compare the expected value of information with the cost of additional observation, verification, or computation when deciding whether
to continue inquiry. High-impact irreversible Actions SHOULD require stronger evidence, broader verifier coverage, and more conservative
uncertainty bounds than low-impact reversible Actions.

### 3.7.6 Propagation and Communication

Processors that transform uncertain inputs MUST either propagate the material uncertainty into their outputs or explicitly state why the
output does not depend on it. Derived assessments MUST retain dependency links, so later invalidation or recalibration can trigger revision.
Conflicting probability assignments MUST remain separate until their scopes, priors, evidence lineage, and model assumptions are reconciled;
blind averaging is prohibited.

User-facing answers and inter-processor messages SHOULD communicate the decision-relevant uncertainty at an appropriate resolution: the
target, estimate or bound, major uncertainty sources, scope, verification status, and what evidence could materially change the assessment.
They MUST NOT present confidence as observed correctness or hide an `INCONCLUSIVE` state behind fluent language.

---

# 4. Global Workspace & Attention

## 4.1 Workspace as a Dynamic Process

The **Global Workspace (GW)** is defined primarily as a **dynamic process of selective information integration and global broadcast**,
rather than merely a static data structure or shared memory buffer.

The Workspace process cycle:
```
Subsystem Proposals ──> Competition ──> Selective Admission ──> Global Broadcast ──> Parallel Subsystem Processing ──> New Competition (↺)
```

The Workspace is NOT:
* Long-term memory,
* The LLM context window,
* The full conversation transcript,
* The complete symbolic knowledge graph.

It represents the active, shared focus of the cognitive system at any given moment.

```
             ┌──────────────────────┐
             │   Global Workspace   │
             │ (Dynamic Process)    │
             └──────────┬───────────┘
                        │ broadcast
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
     Memory          Reasoning           LLM
        ↓                ↓                ↓
     Planner          Prover          Perception
        └────────────────┼────────────────┘
                        ↓
                     Action
```

## 4.2 Workspace Access & Competition

Processors submit candidate Cognitive Objects to the Workspace. Admission MUST be selective and competitive.

A candidate used for reasoning, planning, belief revision, Goal acceptance, or Action selection MUST reference a current, decision-relevant
`UncertaintyAssessment` or explicitly declare that no valid assessment is available. `UNKNOWN` is preferable to a fabricated score. A
Workspace implementation MAY broadcast a bounded summary rather than a processor's complete local uncertainty state, but the summary MUST
identify its target, calculus, scope, assessment version, and material information loss.

Candidates compete based on:
* Goal relevance,
* Novelty and surprise,
* Urgency,
* Uncertainty / conflict level,
* Expected information gain,
* Risk and safety significance.

Workspace priority MUST NOT be a monotonic function of confidence. Low-confidence or out-of-distribution candidates may require high priority
because they expose risk, conflict, surprise, or valuable information-gathering opportunities. The scoring policy MUST keep epistemic quantities
separate from scheduling priority and MUST document how uncertainty-related factors affect admission.

## 4.3 Workspace Broadcast

Once admitted, a Cognitive Object is broadcast to participating processors.

> **Broadcast ≠ Synchronous Function Call**

Broadcasting makes information available; processors independently determine whether to react. Processing MAY be event-driven and asynchronous.
Broadcast MUST preserve the referenced uncertainty assessment or its traceable summary. Admission, broadcast, repetition, and processor uptake
MUST NOT change correctness, verification status, confidence, or evidential weight without a separate justified epistemic transition.

## 4.4 Cognitive Attention

Cognitive Attention allocates processing resources and prioritizes admission to the Workspace based on dynamic cognitive priorities, active goals,
unresolved conflicts, and environmental events.

---

# 5. Cognitive Control & Executive Functions

**Cognitive Control** regulates process execution, resource allocation, and workflow state.

Key responsibilities:
* Scheduling cognitive processors,
* Managing active goals and priorities,
* Resource budget enforcement (tokens, time, memory, tool costs),
* Uncertainty-aware acceptance, abstention, escalation, and value-of-information decisions,
* Interruption and strategy switching,
* Action inhibition and safety gate checks,
* Loop and cycle detection,
* Termination decisions.

GCAS does NOT require Cognitive Control to be a single centralized module ("homunculus"). It MAY be implemented as a Central Executive,
distributed policies, cooperating controllers, or hierarchical monitors.

---

# 6. Cognitive State, Events & Cognitive Bus

## 6.1 State Model vs. Event Model

GCAS decouples the cognitive representation into two complementary abstractions:
* **Cognitive State Model:** The active graph of Cognitive Objects, beliefs, workspace elements, and memory references.
* **Cognitive Event Model:** The reactive stream of state-change events triggering cognitive transitions.

The Global Workspace acts as the selective bridge publishing state changes as cognitive events.

## 6.2 Logical Cognitive Bus Semantics vs. Transport

The **Cognitive Bus** defines **cognitive communication semantics**, NOT physical transport mechanisms.

### Cognitive Bus Semantic Operations
* `publish(CO)` — Submit a Cognitive Object for workspace competition,
* `subscribe(filter)` — Listen for relevant CO types or cognitive events,
* `query(pattern)` — Retrieve active workspace objects,
* `request(processor, Task)` — Solicit processor action,
* `response(task_id, Result)` — Return processor output,
* `interrupt(process_id)` — Halt execution,
* `retract(CO_id)` — Withdraw obsolete object,
* `supersede(old_CO_id, new_CO)` — Replace object.

### Transport Independence
Physical transport MAY be implemented via Unix domain sockets, actor message queues, gRPC, shared memory, event buses,
or in-memory function dispatches. Transport selection MUST NOT alter GCAS semantic operations.

## 6.3 Semantic Cognitive Events

System communication SHOULD use strongly typed semantic events, including:
```
GoalCreated            PlanProposed
ObservationReceived    ActionRequested
HypothesisProposed     ActionCompleted
EvidenceFound          ActionFailed
ConflictDetected       ProofSucceeded / ProofFailed
MemoryRetrieved        ReflectionRaised
UncertaintyEstimated   BeliefUpdated
CorrectnessObserved    CalibrationUpdated
CalibrationDrift       WorkspaceBroadcast
GoalCompleted
```

---

# 7. Neuro-Symbolic Architecture & Neural Interfaces

## 7.1 Generative Cognition vs. Deliberative Cognition

GCAS formalizes a dual-process neuro-symbolic framework using functional terms:

* **Generative Cognition (System 1 Inspired):** Fast, approximate, pattern-based.
  Implemented by LLMs, neural retrieval, and associative models.
  Generates hypotheses, interpretations, analogies, and draft plans.

* **Deliberative Cognition (System 2 Inspired):** Explicit, logical, verifiable, search-based.
  Implemented by symbolic reasoners, theorem provers, SMT solvers, neural tree search, code runtimes,
  and deterministic algorithms. Performs verification, proof, constraint checking, and execution.

`Generative` and `Deliberative` are processor roles, not fixed implementation classes. A neural processor MAY perform deliberative
search, and a symbolic processor MAY use heuristic generation. Processor contracts SHOULD additionally declare relevant properties,
including whether operation is stochastic or deterministic, sound or heuristic, stateful or stateless, and internally inferred or
externally grounded. No processor MAY be considered a verifier merely because it is labeled `Deliberative`.

## 7.2 Neuro-Symbolic Boundary

```
Continuous Representation ──> Neural-Symbolic Bridge ──> Cognitive Objects ──> Symbolic Representation
```

Conversion across the boundary MUST be explicit and observable. Neural representations MUST NOT silently become symbolic facts
without passing through explicit hypothesis and verification stages.

## 7.3 Neural Cognitive State Interface (NCSI) & J-space

GCAS defines an abstract **Neural Cognitive State Interface (NCSI)** allowing neural models
to expose internal signals beyond output tokens:

* Activations and latent representations,
* Uncertainty and entropy metrics,
* Competing internal candidate representations,
* Attention maps and concept directions,
* Steering coordinates.

**J-space** is recognized as one possible internal representational mechanism or source adapter for NCSI. It is not the logical
Global Workspace and its coordinates do not replace Cognitive Objects or explicit epistemic state.

NCSI signals are observations about a neural processor, not evidence for the truth of generated content. Attention, activation,
entropy, concept directions, verbalized confidence, or steering coordinates MAY influence scheduling or trigger verification, but
MUST NOT directly promote a Claim to `VERIFIED` or `ACCEPTED`. Implementations SHOULD empirically validate signal stability,
calibration, and causal relevance for each model and task domain. A raw NCSI signal MUST NOT be labeled as posterior probability of
correctness unless a versioned mapping from that signal has been trained and calibrated against the same declared correctness target.

## 7.4 Bidirectional Neural Steering

NCSI SHOULD support bidirectional control:
1. **Neural → Cognitive:** Exposing internal neural state as candidate Cognitive Objects.
2. **Cognitive → Neural:** Steering neural generation using cognitive state via prompt construction, activation steering,
constrained decoding, or adapter selection.

---

# 8. Memory Architecture & Context Dynamics

## 8.1 Memory Taxonomy

GCAS distinguishes six memory functions:

1. **Working Memory:** Short-term, task-specific active state (closely coupled with the Global Workspace).
2. **Episodic Memory:** Temporally grounded records of system experiences, actions, and observations.
3. **Semantic Memory:** Generalized concepts, facts, rules, and domain knowledge decoupled from specific episodes.
4. **Procedural Memory:** Reusable skills, strategies, operational workflows, and tool-use scripts.
5. **Prospective Memory:** Intentions, scheduled triggers, and deferred tasks to be executed under future conditions.
6. **Metacognitive Memory:** Historical logs of reasoning performance, failure modes, processor reliability, and tool success rates.

## 8.2 Memory Is Not Conversation History

GCAS explicitly rejects:
```
Memory = appending previous conversation transcript to the LLM prompt
```
Transcripts record *what was said*; memory stores *what was learned, verified, and structured*.

## 8.3 Retrieval, Consolidation & Controlled Forgetting

* **Selective Retrieval:** Memory retrieval MUST be driven by current goals, workspace state, entity relations,
  and uncertainty signals—not blanket context window expansion.
* **Memory Consolidation:** Asynchronous transformation of raw episodic records into validated semantic and procedural knowledge.
* **Controlled Forgetting:** Retention MUST be governed by relevance, typed uncertainty, utility, and decay policies. Forgetting, compression,
  summarization, supersession, and archival are essential system features.

Retrieval is an epistemically neutral operation: retrieving a CO MUST NOT increase its epistemic or verification status. Retrieved
objects MUST enter active cognition through a **guarded merge** that preserves current observations, scope, provenance, temporal
validity, contradictions, and the identity of the originating episode. Episodic retrieval SHOULD supplement missing context rather
than replace freshly observed state. A replacement-style merge requires an explicit policy decision and audit record.

Memory admission and consolidation SHOULD record why an object was retained, its intended memory role, retention or revalidation
conditions, and the evidence supporting any semantic generalization. Summaries MUST retain derivation links to the records summarized.

## 8.4 Context Reconstruction & Context Rot Mitigation

To prevent context degradation (*context rot*), prompts provided to LLMs MUST be treated as **transient dynamic projections** of the current cognitive state:

```
Current Goal + Workspace State + Selected Memories + Active Constraints ──> Reconstructed Prompt Context
```

Context window size increases alone DO NOT replace dynamic context reconstruction.

---

# 9. Execution, Environment & Scientific Cognition

## 9.1 Execution Runtime Separation

GCAS strictly separates cognition (planning, reasoning) from execution (tool calls, code running).

Runtimes MAY include REPLs, shell environments, containers, API clients, databases, or physical actuators. Runtimes MUST expose explicit,
authoritative state rather than requiring LLMs to guess environment state.

Successful execution verifies only the reported execution result within the observed environment and declared reproducibility scope.
It MUST NOT automatically verify the semantic correctness of the Action, the premises that motivated it, or satisfaction of its parent Goal.

## 9.2 Environment Model & Reproducible Actions

Systems SHOULD maintain an explicit model of environment state, distinguishing `believed state` from `freshly observed state`.

Actions SHOULD generate **Reproducibility Records** containing:
```
input payload | code executed | environment hash | dependencies | parameters | output hashes | provenance
```

## 9.3 Scientific Reasoning Cycle

GCAS natively supports explicit scientific reasoning:
```
Question ──> Hypothesis ──> Prior ──> Prediction ──> Experiment ──> Observation ──> Evidence ──> Evaluation ──> Posterior / Belief Update
```

## 9.4 Metacognition, Loop Detection & Failure States

* **Metacognition:** The system MUST monitor its own operation (e.g., detecting missing evidence, assumption dependencies, cycling).
* **Loop Detection:** Progress monitoring MUST interrupt repeating tool errors, oscillating plans, or stagnant subgoals.
* **Explicit Failure Outcomes:** The system MUST treat non-certainty as a valid, first-class outcome rather than fabricating answers:
```
UNKNOWN | UNVERIFIED | INCONCLUSIVE | CONFLICTING_EVIDENCE | INSUFFICIENT_INFORMATION | FAILED
```

---

# 10. Self-Modification & System Evolution

## 10.1 Levels of Self-Modification

GCAS categorizes self-modification into six levels:
* **L0 — Workspace State:** Modifying active working state (routine cognition).
* **L1 — Memory:** Adding/updating beliefs and episodic records.
* **L2 — Procedures:** Refining tools, prompt templates, and operational skills.
* **L3 — Policies:** Modifying attention priorities, retrieval thresholds, or safety checks.
* **L4 — Model Parameters:** Fine-tuning or updating neural weights/adapters.
* **L5 — Architecture:** Modifying cognitive processors or core bus semantics.

Higher levels require progressively stricter verification. Architectural modification (L5) MUST NOT occur as an unconstrained cognitive action.

## 10.2 Self-Modification Governance Pipeline

Self-modification proposals SHOULD follow a strict pipeline guided by `Proposal ≠ Deployment`:
```
Proposal ──> Static Analysis ──> Sandbox Trial ──> Verification ──> Policy Approval ──> Deployment ──> Monitoring (with Rollback)
```

---

# 11. Normative Cognitive Invariants & Conformance

## 11.1 Cognitive Invariants (I1–I12)

A compliant GCAS implementation MUST satisfy the following invariants:

* **I1:** Generated content is candidate cognition (`HYPOTHESIS`), NOT automatic knowledge.
* **I2:** Persistent knowledge MUST carry provenance and verification metadata.
* **I3:** Typed uncertainty, its conditioning evidence, update history, calibration scope, and temporal validity MUST remain explicitly representable.
* **I4:** Contradictory claims MUST NOT silently overwrite one another.
* **I5:** External state MUST be observed from the environment when accessible, not inferred purely from internal memory.
* **I6:** Actions MUST produce observable, auditable results.
* **I7:** Key derivations and execution results SHOULD be reproducible where environment permits.
* **I8:** Failure (`UNKNOWN`, `FAILED`) MUST remain an acceptable and preferred outcome over fabricated certainty.
* **I9:** Persistent memory MUST NOT depend solely on LLM context windows.
* **I10:** No individual cognitive processor is assumed infallible.
* **I11:** Correctness, verification status, and confidence MUST remain distinct; no confidence value establishes correctness or verification.
* **I12:** Material uncertainty MUST be propagated into predictions and decisions or its omission MUST be declared and justified.

## 11.2 Minimal Conformance Requirements (GCAS-Core 0.3)

To claim **GCAS-Core 0.3** compliance, a system MUST implement at minimum:
1. Explicit Cognitive Objects with metadata, 3-axis epistemic model, provenance, and versioned Uncertainty Assessments,
2. Epistemic distinction between generated hypotheses and verified beliefs,
3. Bounded Global Workspace process with selective admission/broadcast,
4. At least two distinct specialized cognitive processors (Generative + Deliberative),
5. Explicit memory architecture separate from conversation prompt history,
6. Recurrent cognitive cycle with progress and loop monitoring,
7. Separated execution runtime with auditable Action/Result semantics,
8. Explicit representation of typed uncertainty, correctness targets, calibration scope, temporal validity, and failure states,
9. Uncertainty-aware acceptance and abstention rules that do not equate confidence with correctness.

A system does NOT require Bayesian inference, a specific neural model, J-space, Scheme, Lean, or Guix to achieve GCAS-Core 0.3 conformance.
If it does not implement Bayesian inference, it MUST still declare the uncertainty calculus, semantics, assumptions, operations, and limitations
used to satisfy the uncertainty requirements. Bayesian conformance is a separate, additive profile defined in §14.

---

# 12. Reference Architecture & Reactive Event Graph

## 12.1 Reactive Event Graph Architecture Diagram

```text
                              ┌────────────────┐
                              │  ENVIRONMENT   │
                              └───────┬────────┘
                                      │
                                 perception
                                      │
                                      ▼
                         ┌──────────────────────────┐
                         │    GLOBAL WORKSPACE      │
                         │   (Dynamic Selection)    │
                         └────────────┬─────────────┘
                                      │
                         ┌────────────┼────────────┐
                         │            │            │
                         ▼            ▼            ▼
                     Generative   Deliberative   Memory
                     Cognition    Cognition      System
                         │            │            │
                         └────────────┼────────────┘
                                      │
                                  proposals
                                      │
                                      ▼
                              Cognitive Control
                                      │
                                  decisions
                                      │
                                      ▼
                                   Planner
                                      │
                                      ▼
                                   Actions
                                      │
                                      ▼
                              ENVIRONMENT
```

Uncertainty is a cross-cutting state and feedback process rather than a standalone oracle:

```text
Observations / Evidence / Model Assumptions
                    │
                    ▼
        Bayesian or Declared Updater
                    │
                    ▼
       Versioned Uncertainty State (U)
          │          │           │
          ▼          ▼           ▼
     Prediction   Cognitive   Rendering /
     & Planning    Control     Abstention
          │          │           │
          └──────────┴───────────┘
                    │
        Correctness Outcomes & Calibration
                    └─────────── feedback ──> Updater
```

## 12.2 GAIA Reference Implementation Mapping (Non-Normative)

GAIA may implement GCAS using the following stack. These mappings are non-normative; altering any technology choice MUST NOT alter GCAS semantics.

| GCAS Concept | Possible GAIA Implementation |
| :--- | :--- |
| **Cognitive Bus** | Goblins actor runtime / Unix domain sockets / IPC |
| **Cognitive Objects** | Scheme records / S-expressions / AtomSpace nodes |
| **Global Workspace** | Dedicated AtomSpace store / in-memory workspace actor |
| **Generative Cognition** | Local open-weight LLM (e.g., Llama/Qwen via llama.cpp) |
| **Neural Cognitive State (NCSI)** | J-space adapter / internal activation probes |
| **Deliberative Cognition** | OpenCog Hyperon (MeTTa) / Lean 4 / Z3 SMT |
| **Execution Runtime** | GNU Guile REPL |
| **Reproducible Environment** | GNU Guix |
| **Persistent Memory** | AtomSpace + persistent disk database |
| **Uncertainty State** | Versioned Cognitive Objects plus a declared probabilistic/statistical inference backend |

---

# 13. GCAS 0.3 Operational Semantics

GCAS 0.3 defines cognition as a recurrent, event-driven transition system over explicit Cognitive State. These semantics describe
observable architectural behavior, not a required scheduler, programming language, database, or physical transport.

## 13.1 Abstract Machine

At logical time $t$, a GCAS process is represented by:

```text
S_t = <O_t, J_t, U_t, W_t, G_t, P_t, M_t, B_t, X_t>
```

where:

* `O` is the durable set of versioned Cognitive Objects,
* `J` is the justification, provenance, contradiction, and supersession graph,
* `U` is the uncertainty projection over `O` and `J`, indexing `UncertaintyAssessment`, calibration, mapping, and calculus-declaration COs
  together with their dependencies; it is not an independent source of epistemic records,
* `W` is the bounded Workspace state, including pending and active candidates,
* `G` is the set of Goals and their operational states,
* `P` is the set of active Cognitive Processes and processor capabilities,
* `M` is the set of memory stores, indexes, and consolidation metadata,
* `B` is the remaining resource and failure budget,
* `X` is the latest authoritative observations of accessible environments.

A semantic Cognitive Event $e_t$ triggers a transition:

```text
transition(S_t, e_t, processor, policy) -> <S_(t+1), emitted-events, effects>
```

Every committed transition MUST identify its triggering event, responsible processor or policy, input COs, created or superseded COs,
resource effects, and causal parent. A transition that changes durable epistemic state MUST be auditable after process termination.

Formally, if $A_t = \{o \in O_t \mid type(o)=\texttt{UncertaintyAssessment}\}$, then `U_t` is a deterministic, rebuildable projection of
$A_t`, related calibration and calculus COs, and the applicable edges in `J_t`. Creating, updating, converting, invalidating, or calibrating
an assessment changes `O` and `J`; `U` makes that state operationally queryable but MUST NOT contain an authoritative assessment absent from `O`.

## 13.2 Events, Effects, and Ordering

A Cognitive Event reports a semantic occurrence; it does not by itself authorize an external effect. External or persistent effects
MUST cross the appropriate Action, Memory Admission, or governance boundary.

Implementations MAY process independent events concurrently. For causally related events they MUST preserve a recoverable partial order.
Each event SHOULD carry `event_id`, `process_id`, `goal_id`, `caused_by`, `state_version`, `producer`, and `timestamp`. When deterministic
replay is impossible, the system MUST record nondeterministic inputs and scheduling decisions sufficiently for probabilistic reproduction.

Duplicate delivery MUST NOT cause duplicate terminal outcomes or ungoverned repeated effects. Implementations MUST define idempotency or
deduplication behavior for Actions, terminal events, belief transitions, and Memory Admission.

## 13.3 Processor Contracts and Capability Claims

Each processor MUST declare the CO and event types it accepts and may emit, the external capabilities it requires, and whether it may
request effects. A processor capability declaration is itself a scoped Claim subject to observation and revision from performance history.

GCAS distinguishes logical roles that MAY be implemented by one or many physical modules:

* **Generator:** proposes hypotheses, interpretations, candidate plans, or candidate actions;
* **Retriever:** proposes existing COs relevant to active state;
* **Planner:** constructs Plans, subgoals, and acceptance dependencies;
* **Evaluator:** produces typed assessments or Evidence;
* **Verifier:** evaluates a declared verification target under an explicit contract;
* **Executor:** crosses an Action boundary and observes its result;
* **Controller:** schedules work, enforces budgets, and decides termination;
* **Consolidator:** proposes durable memory admission, generalization, supersession, or forgetting;
* **Renderer:** constructs a user-facing answer from terminal Goal state and accepted supporting COs.

Role separation is semantic rather than necessarily physical. If the same physical model occupies generator and verifier roles, the
verification record MUST declare this shared failure source; the result MUST NOT be represented as independent verification.

## 13.4 Cognitive Object Lifecycle

Lifecycle state is independent of epistemic status. The normal operational lifecycle is:

```text
CREATED -> PROPOSED -> ADMITTED -> ACTIVE -> ARCHIVED
                    \-> RETRACTED
any non-terminal version -> SUPERSEDED by a linked new version
```

* `CREATED`: validated as a well-formed CO and added to Cognitive State;
* `PROPOSED`: submitted as a candidate for Workspace admission or another governed decision;
* `ADMITTED`: selected during a Workspace round;
* `ACTIVE`: broadcast as part of the current bounded focus;
* `RETRACTED`: withdrawn from competition without erasing history;
* `SUPERSEDED`: replaced for current use by a linked version;
* `ARCHIVED`: retained durably but excluded from ordinary active selection.

Workspace selection MUST NOT change epistemic or verification status. Retraction from Workspace MUST NOT delete the CO from durable state.

## 13.5 Workspace Round Semantics

A conforming Workspace round MUST expose the following logical stages:

```text
COLLECT -> ELIGIBILITY -> SCORE -> ADMIT -> BROADCAST -> REACT -> RELEASE
```

1. **Collect:** processors submit typed candidate COs with goal and process scope.
2. **Eligibility:** policy removes malformed, expired, unauthorized, or out-of-scope candidates; rejection reasons are recorded.
3. **Score:** eligible candidates receive comparable scheduling priority from declared factors such as goal relevance, novelty,
   urgency, uncertainty, conflict, expected information gain, risk, and cost. Scheduling priority is not confidence and MUST NOT be
   interpreted as an epistemic quantity.
4. **Admit:** at most the bounded capacity is selected. Tie-breaking and nondeterministic choices MUST be traceable.
5. **Broadcast:** admitted COs become available to subscribed processors through semantic events.
6. **React:** processors independently produce proposals, requests, or no response.
7. **Release:** active focus is cleared or carried forward under an explicit retention policy; durable COs remain in Cognitive State.

A Workspace implementation MAY fuse stages or execute them asynchronously, provided the observable semantics are equivalent. Workspace
capacity and scoring policy MUST be configurable and evaluable; GWT inspiration alone does not establish their effectiveness.
Decision-relevant candidates MUST satisfy the metacognitive accompaniment and bounded-summary requirements of §4.2–§4.3.

## 13.6 Epistemic Transition Semantics

Epistemic transitions MUST be justified by new CO versions and graph relations. Minimum rules are:

1. Model-generated content begins as `HYPOTHESIS/UNVERIFIED` with `LLM` provenance.
2. User and sensor input begins as an `Observation`; observation does not imply truth.
3. Retrieval, broadcast, repetition, source count without lineage analysis, or model consensus does not promote status.
4. An Evaluator or Verifier creates a typed Verification or Evidence record declaring target, method, scope, inputs, outcome, coverage,
   and known shared failure sources.
5. `FORMALLY_VERIFIED/DERIVATION_VALIDITY` establishes only that the conclusion follows in the declared formal system from the declared premises.
6. An `EXECUTION_RESULT` verification establishes only what was observed from that execution in its recorded environment.
7. Promotion to `ACCEPTED` requires an explicit domain or Goal acceptance policy whose evidence requirements are satisfied.
8. Opposing evidence or incompatible scoped Claims create a `Conflict` CO. Conflict MUST NOT be resolved by silent deletion or scalar averaging.
9. Refutation, expiration, or invalidation of a supporting premise makes dependent Claims eligible for re-evaluation. Historical acceptance remains auditable.
10. `UNKNOWN`, `INCONCLUSIVE`, and `CONFLICTING_EVIDENCE` are valid outcomes and require no fabricated balancing Claim.
11. A probabilistic update creates a new `UncertaintyAssessment` linked to its prior assessment, evidence, likelihood/model, inference method,
    and affected target; it does not overwrite the earlier belief state.
12. Confidence MUST NOT change verification or epistemic status without the evidence and policy transition independently required for that change.

GCAS 0.3 uses Bayesian probability as reference semantics for quantified belief update and prediction under §3.7.2, while GCAS-Core 0.3
remains calculus-pluralist. Bayesian, credal, evidential, conformal, interval, truth-maintenance, and paraconsistent mechanisms MAY coexist
when their targets, domains, assumptions, and semantics are declared. Implementations MUST follow §3.7.3 and MUST NOT combine heterogeneous
uncertainty values as if they shared an undeclared scale. A system claims Bayesian semantics only through the additive profile in §14.

## 13.7 Goal and Process Semantics

Every executable Goal MUST declare:

* its scope and parent Goal, if any,
* observable completion criteria or a named acceptance contract, including its correctness target,
* admissible evidence and required verification target,
* resource and failure budgets,
* terminal outcomes available when the criteria cannot be established,
* uncertainty-sensitive acceptance, abstention, and escalation rules appropriate to error cost and Action reversibility.

Goal operational states are:

```text
PENDING | ACTIVE | SATISFIED | INCONCLUSIVE | FAILED | CANCELLED
```

Goal state is distinct from process state and from the epistemic status of any individual Claim. A successful Action or accepted
intermediate Claim MUST NOT set a Goal to `SATISFIED` unless a Goal Verifier establishes `GOAL_SATISFACTION` under the Goal's acceptance
contract. Open-ended questions MAY use an acceptance contract based on adequate evidence coverage and calibrated abstention rather than
an executable oracle, but the weaker assurance MUST be declared.

Subgoals inherit neither truth nor completion automatically. Their relation to the parent Goal and the rule for composing their evidence
MUST be explicit.

## 13.8 Governed Action Transaction

Every effectful Action follows this logical transaction:

```text
Action Proposal
  -> Policy and Capability Check
  -> Authorization
  -> Execution
  -> Result or Failure Observation
  -> Reproducibility Record
  -> Evaluation
  -> Goal/Belief Reconciliation
```

Authorization MUST be bound to the exact or explicitly parameterized Action, capability scope, environment, and process. Failure before
execution MUST NOT be represented as an environment Result. Late or duplicate callbacks after cancellation or termination MAY be retained
as observations but MUST NOT reopen a terminal Goal or produce a second terminal response.

Runtime governance is not assumed complete. Implementations SHOULD distinguish statically guaranteed properties, runtime-enforced
properties, best-effort detections, sandbox containment, and properties known to be undecidable or outside monitor visibility.

## 13.9 Memory Retrieval and Consolidation Process

Memory retrieval produces candidate COs plus retrieval metadata; it does not copy epistemic authority into the active Goal. Before a
retrieved object affects planning or belief, guarded merge MUST check goal relevance, scope, temporal validity, provenance, contradiction,
and relation to fresh observations.

Consolidation from episodic into semantic or procedural memory is a governed epistemic transition. It MUST preserve source episodes and
MUST record any abstraction, summarization, loss, or generalization. A semantic memory Claim derived solely from model-generated summaries
remains unverified unless independently evaluated. Controlled forgetting MUST preserve the justification needed to understand surviving Claims.

## 13.10 Metacognitive Process

Metacognition operates on explicit first- and higher-order COs representing process state, capabilities, budgets, progress, failures,
strategy history, and uncertainty. It MAY reuse ordinary retrieval, reasoning, planning, and learning mechanisms; GCAS does not require a
dedicated metacognitive homunculus.

Metacognitive outputs are hypotheses about system operation unless grounded by trace evidence or external evaluation. A processor's
self-report of confidence, success, or error is not authoritative merely because it concerns itself. Metacognitive memory SHOULD support
empirical revision of capability Claims such as verifier coverage, tool reliability, or expected strategy cost.

## 13.11 Progress, Replanning, and Termination

Control MUST detect bounded non-progress using declared signals such as repeated equivalent Actions, unchanged unresolved criteria,
oscillating Plans, repeated tool failures, exhausted budgets, or absence of eligible proposals. Replanning SHOULD consume a typed
Reflection containing the failed criterion, relevant observations, and remaining budgets rather than replaying an undifferentiated transcript.

A process MUST emit exactly one terminal outcome visible to its caller:

```text
COMPLETED | INCONCLUSIVE | FAILED | CANCELLED | INTERRUPTED
```

`COMPLETED` requires a `SATISFIED` Goal and accepted `GOAL_SATISFACTION` verification. Budget exhaustion, lack of verifier coverage,
unresolved conflict, and insufficient information normally produce `INCONCLUSIVE` or `FAILED` according to the Goal contract. Terminal
events MUST include the reason, remaining unresolved criteria, and supporting CO identifiers.

## 13.12 Normative Scientific Inquiry Trace

For the inquiry *"Is claim X from publication Y supported?"*, a conforming process exposes at least the following logical trace.
Physical implementations MAY interleave or repeat stages but MUST preserve their epistemic boundaries.

| Stage | Trigger | Required output and invariant |
| :--- | :--- | :--- |
| 1. Intake | User input | `Question` Observation; user text is not a verified Claim. |
| 2. Goal formation | `ObservationReceived` | Goal with scope, completion criteria, evidence policy, and budgets. |
| 3. Initial activation | `GoalCreated` | Goal proposed to a bounded Workspace round. |
| 4. Memory retrieval | Goal broadcast | Relevant CO candidates with retrieval metadata; no status promotion. |
| 5. Context projection | Retrieved candidates evaluated | Guarded merge of Goal, current observations, selected memories, and constraints. |
| 6. Hypothesis generation | Context available | One or more `HYPOTHESIS/UNVERIFIED` Claims with LLM provenance. |
| 7. Evidence acquisition | Hypothesis broadcast | Source Observations and Evidence with resolvable provenance and temporal scope. |
| 8. Competition | Multiple candidates pending | Recorded eligibility, scoring, and admission; selection is not verification. |
| 9. Deliberation | Evidence/hypothesis admitted | Derivations, tests, counterexamples, or verification requests with declared targets. |
| 10. Evaluation | Result/evidence available | Typed Verification records stating scope, coverage, outcome, and failure dependencies; evaluated correctness remains distinct from estimated confidence. |
| 11. Conflict handling | Incompatible Claims detected | Explicit Conflict CO; preserve both claims and their justification graphs. |
| 12. Belief revision | Acceptance policy evaluated | Versioned prior-to-posterior Uncertainty Assessment and new Claim status, or an explicit inconclusive outcome; correlated evidence is not double-counted. |
| 13. Reflection | Progress or failure event | Trace-grounded assessment and, when useful, revised strategy under remaining budget. |
| 14. Goal verification | Candidate answer available | Independent or dependency-declared verification of `GOAL_SATISFACTION`. |
| 15. Rendering | Goal terminal | Answer derived from terminal state, including verification status, calibrated confidence or bounds where supported, major uncertainty sources, conflicts, and sources. |
| 16. Consolidation | Process terminal | Governed episodic record and optional semantic/procedural proposals; no automatic truth promotion. |

The minimum correct result may be `INCONCLUSIVE`. A fluent answer unsupported by the recorded trace is non-conforming.

## 13.13 Assurance and Verifier Independence

Verification records SHOULD declare an assurance class:

* **V0 — Self-report:** the generating processor assesses its own output;
* **V1 — Re-sampling or prompt separation:** the same model family is reused with partially shared failure modes;
* **V2 — Model diversity:** a distinct learned evaluator is used, but training data or representational biases may overlap;
* **V3 — External deterministic check:** a test, parser, solver, theorem prover, or reproducible computation checks a bounded property;
* **V4 — Independent empirical observation:** a separately governed source or measurement checks a world-facing claim;
* **V5 — Formal proof plus verified grounding:** derivation validity and the required grounding assumptions are separately established.

Higher class is not universally better and does not imply wider coverage. Goal policies SHOULD require the lowest class sufficient for
risk and domain while recording uncovered properties. Multiple verifiers increase assurance only to the extent that their failure modes
are independent and their evidence is relevant to the same scoped Claim.

---

# 14. GCAS 0.3 Conformance and Empirical Evaluation

## 14.1 GCAS-Process Conformance

In addition to GCAS-Core requirements, a claim of **GCAS-Process 0.3** conformance MUST demonstrate:

1. versioned CO lifecycle separate from epistemic status;
2. durable causal transition records and duplicate-safe terminal behavior;
3. explicit verification targets, scopes, coverage, and shared verifier dependencies;
4. Workspace rounds with bounded capacity and observable collect-to-release semantics;
5. justification, contradiction, supersession, and invalidation relations;
6. Goals with acceptance contracts, budgets, and exactly one terminal process outcome;
7. governed Action transactions in which execution success is distinct from Goal satisfaction;
8. epistemically neutral retrieval and guarded memory merge;
9. trace-grounded Reflection and bounded non-progress handling;
10. versioned uncertainty state and `UncertaintyAssessment` dependencies across relevant transitions;
11. uncertainty-aware Goal contracts that distinguish correctness, verification, confidence, acceptance, and abstention;
12. at least one complete implementation-independent inquiry trace conforming to §13.12.

Architectural conformance establishes that these boundaries exist and behave according to the specification. It does not establish broad
competence, calibrated factuality, safety, general intelligence, consciousness, or superiority over a simpler system.

## 14.2 GCAS-Uncertainty Conformance

A claim of **GCAS-Uncertainty 0.3** conformance MUST demonstrate, for each covered domain:

1. declared correctness targets and uncertainty quantities with scope, units, and semantics;
2. versioned priors, likelihood or observation models, posteriors, and posterior predictive assessments for at least one empirical Claim class;
3. explicit conditioning evidence, assumptions, provenance lineage, and dependence handling that prevents unjustified evidence multiplication;
4. typed aleatoric, epistemic, distributional, and computational uncertainty where material;
5. declared exact or approximate inference methods, budgets, diagnostics, and known failure modes;
6. a calibration protocol tied to evaluated correctness outcomes, with sample counts, proper scoring rules, and distribution-shift handling;
7. uncertainty propagation across a multi-stage derivation, prediction, or Plan;
8. decision policies that combine predictive uncertainty with error costs, utility or risk constraints, and valid abstention/escalation outcomes;
9. rendering that never labels estimated confidence as correctness or verification.

Conformance is scoped. A system conforming for code-test outcomes does not thereby conform for medical Claims, physical-world predictions,
open-ended factual answers, or the reliability of its own metacognitive reports.

## 14.3 Required Evaluation Separation

Implementations SHOULD maintain four distinct evaluation layers:

* **Invariant tests:** deterministic checks of transition, lifecycle, authorization, persistence, and terminal semantics;
* **Competence tests:** task-specific executable or human-validated correctness criteria;
* **Uncertainty tests:** calibration, sharpness, proper scores, interval coverage, abstention quality, and decision loss under distribution shift;
* **Architectural evidence:** controlled comparisons showing whether GCAS mechanisms improve reliability, cost, or long-horizon behavior.

These layers MUST NOT be reported as interchangeable. A scripted good proposal tests orchestration, not whether a live model will produce it.

## 14.4 Recommended Baselines, Ablations, and Metrics

Empirical claims for GCAS SHOULD compare, where feasible:

1. a model-only or single-turn baseline;
2. transcript or maximum-context accumulation;
3. retrieval-augmented generation without epistemic control;
4. tiered memory without GCAS verification semantics;
5. full GCAS and ablations removing Workspace competition, guarded merge, provenance, external verification, Bayesian update,
   calibration, uncertainty propagation, uncertainty-aware abstention, or Reflection.

Primary reliability metrics SHOULD include false acceptance rate, correct abstention, risk-coverage behavior, provenance and citation
fidelity, contradiction retention, stale-memory use, terminal-response rate, repeated non-progressing Actions, task success, log loss,
Brier score, calibration curves with sample counts, interval coverage, posterior predictive checks, realized decision loss, model and tool
calls, tokens, latency, and cost. Metrics MUST name the correctness target used as ground truth. Long-context evaluations SHOULD vary
evidence position and irrelevant context. Long-horizon evaluations SHOULD report success as a function of task length rather than only
aggregate pass rate.

# 15. Open Research Questions Beyond GCAS 0.3

1. **Workspace Capacity:** How should workspace capacity bounds be mathematically or empirically defined?
2. **Competition Policy:** Which competition and broadcast policies produce measurable gains over simpler routing mechanisms?
3. **Semantic Identity:** How should implementations deduplicate equivalent content while retaining distinct assertions, sources, and histories?
4. **Evidence Combination:** Which likelihood models and dependence structures combine heterogeneous evidence without double-counting or
   collapsing it into a misleading scalar, and when should non-Bayesian representations be preferred?
5. **Belief Revision:** When should GCAS use truth-maintenance, assumption-based, probabilistic, or paraconsistent semantics?
6. **Source Independence:** How should shared ancestry, model dependence, and citation copying reduce the effective weight of corroboration?
7. **Retention and Revalidation:** What governed forgetting, decay, and revalidation policies minimize both stale-memory use and catastrophic loss?
8. **Distributed Consistency:** Which causal ordering, transaction, rollback, and vector-clock guarantees are required across deployments?
9. **Open-Ended Goals:** How can acceptance contracts specify adequate evidence and coverage where no complete oracle exists?
10. **Verifier Coverage:** How should correlated failure modes and untested properties be quantified across mixed assurance classes?
11. **Metacognitive Learning:** Which control capabilities should be fixed, learned, or learned under a formally constrained policy?
12. **NCSI Faithfulness:** What minimal interface and causal interventions establish that a neural-state signal is stable and behaviorally meaningful?
13. **Symbol Grounding:** How can continuous neural concepts be aligned with symbolic objects without claiming false equivalence?
14. **Safe Neural Steering:** How can activation steering be bounded, audited, and reversed without degrading instruction following?
15. **Resource-Aware Scheduling:** How should risk, information value, monetary cost, tokens, time, and hardware jointly affect attention?
16. **Runtime Governance Limits:** Which unsafe traces cannot be prevented by runtime policy enforcement alone and require upstream guarantees?
17. **Transfer and Generalization:** Which GCAS mechanisms improve reliability across models, domains, and task horizons rather than on one benchmark?
18. **Uncertainty Under Open Worlds:** How should priors, model expansion, unknown unknowns, and calibration failure be represented when the
    current hypothesis space is itself inadequate?

---

# 16. Research Grounding (Non-Normative)

GCAS does not prescribe the following theories or mechanisms as implementation dependencies. They ground design choices and define
comparison points that implementations SHOULD address when making scientific claims:

* **Common cognitive architecture and metacognition:** the Standard Model/Common Model motivates reusable functional components and explicit
  control state; GCAS keeps control distributed and empirically inspectable rather than postulating a privileged homunculus.
* **Global Workspace Theory and metacognition:** motivate bounded competition and broadcast together with a confidence or uncertainty
  accompaniment that lets heterogeneous representations be weighed and compared. Predictive Global Neuronal Workspace models establish
  that approximate Bayesian inference and Workspace-style broadcast can coexist; GCAS adopts the functional boundary without making a
  consciousness claim, prescribing a neuronal mechanism, or treating broadcast as verification.
* **Truth-maintenance and assumption-based reasoning:** motivate versioned justification graphs, dependency invalidation, and preservation of
  conflicting claims.
* **Probabilistic machine learning and Bayesian inference:** motivate representing uncertainty over observations, parameters, model structure,
  predictions, and Action outcomes; learning is operationalized as a versioned prior-to-posterior transition and prediction as posterior
  marginalization rather than a point estimate. Bayesian workflow and model criticism motivate predictive checks, sensitivity analysis,
  and explicit responses to misspecification rather than conditioning alone.
* **Plural uncertainty and calibrated prediction:** Subjective Logic, credal sets, formal bounds, and conformal prediction motivate typed
  uncertainty where a single posterior is unavailable or inappropriate. Proper scoring rules motivate sharpness subject to calibration;
  dataset-shift results motivate scope invalidation, abstention, and re-evaluation. GCAS does not mandate a universal scalar confidence value.
* **Executable world models and scientific workflows:** motivate separating proposal, execution, derivation checking, empirical observation,
  and Goal satisfaction.
* **Long-context and memory research:** motivates dynamic context projection and guarded merge instead of treating a growing transcript or
  retrieved text as current belief.
* **Hallucination detection and self-correction research:** motivates scoped verification and explicit verifier dependence; fluent self-review
  is a weak assurance class, not proof.
* **Runtime policy enforcement limits:** motivate layered governance and explicit acknowledgement that no monitor can guarantee arbitrary
  semantic safety properties for unrestricted agents.

Selected references:

1. J. E. Laird, C. Lebiere, and P. S. Rosenbloom, “A Standard Model of the Mind,” *AI Magazine* 38(4), 2017. <https://doi.org/10.1609/aimag.v38i4.2744>
2. J. E. Laird et al., “Unified, Comprehensive Metacognition within Common Model,” *AGI-26*, 2026. <https://doi.org/10.1007/978-3-032-33195-3_1>
3. H. Schneider, “Improving Long-Horizon Task Completion in a Proto-AGI Cognitive Architecture: A Memory-Centric Approach,” *AGI-26*, 2026. <https://doi.org/10.1007/978-3-032-33195-3_20>
4. S. Rodionov, “Executable World Models for ARC-AGI-3 in the Era of Coding Agents,” *AGI-26*, 2026. <https://doi.org/10.1007/978-3-032-33195-3_15>
5. P. C. Tiffany III, “The Hypothesis Surface: An Operational Epistemology for Autonomous Research,” *AGI-26*, 2026. <https://doi.org/10.1007/978-3-032-33195-3_25>
6. S. Shukla and H. Joshi, “Fundamental Limits of Runtime Policy Enforcement in Multi-agent AGI Systems,” *AGI-26*, 2026. <https://doi.org/10.1007/978-3-032-33195-3_21>
7. J. Doyle, “A Truth Maintenance System,” *Artificial Intelligence* 12(3), 1979. <https://doi.org/10.1016/0004-3702(79)90008-0>
8. J. de Kleer, “An Assumption-based TMS,” *Artificial Intelligence* 28(2), 1986. <https://doi.org/10.1016/0004-3702(86)90080-9>
9. W3C, “PROV-O: The PROV Ontology,” 2013. <https://www.w3.org/TR/prov-o/>
10. N. F. Liu et al., “Lost in the Middle,” *TACL* 12, 2024. <https://doi.org/10.1162/tacl_a_00638>
11. R. Kamoi et al., “When Can LLMs Actually Correct Their Own Mistakes?,” *TACL* 12, 2024. <https://doi.org/10.1162/tacl_a_00713>
12. S. Farquhar et al., “Detecting Hallucinations in Large Language Models Using Semantic Entropy,” *Nature* 630, 2024. <https://doi.org/10.1038/s41586-024-07421-0>
13. G. Marra et al., “From Statistical Relational to Neuro-Symbolic Artificial Intelligence,” *Artificial Intelligence* 328, 2024. <https://doi.org/10.1016/j.artint.2023.104062>
14. A. Jøsang, *Subjective Logic*, Springer, 2016. <https://doi.org/10.1007/978-3-319-42337-1>
15. Z. Ghahramani, “Probabilistic Machine Learning and Artificial Intelligence,” *Nature* 521, 2015, pp. 452–459.
    <https://doi.org/10.1038/nature14541>
16. N. Shea and C. D. Frith, “The Global Workspace Needs Metacognition,” *Trends in Cognitive Sciences* 23(7), 2019, pp. 560–571.
    <https://doi.org/10.1016/j.tics.2019.04.007>
17. C. J. Whyte, “Integrating the Global Neuronal Workspace into the Framework of Predictive Processing,”
    *Consciousness and Cognition* 73, 2019, 102763. <https://doi.org/10.1016/j.concog.2019.102763>
18. C. J. Whyte and R. Smith, “The Predictive Global Neuronal Workspace,” *Progress in Neurobiology* 199, 2021, 101918.
    <https://doi.org/10.1016/j.pneurobio.2020.101918>
19. A. Gelman et al., “Bayesian Workflow,” 2020. <https://arxiv.org/abs/2011.01808>
20. T. Gneiting and A. E. Raftery, “Strictly Proper Scoring Rules, Prediction, and Estimation,”
    *Journal of the Royal Statistical Society: Series B* 69(2), 2007, pp. 243–268.
    <https://doi.org/10.1111/j.1467-9868.2007.00587.x>
21. Y. Ovadia et al., “Can You Trust Your Model's Uncertainty? Evaluating Predictive Uncertainty under Dataset Shift,” *NeurIPS*, 2019.
    <https://papers.nips.cc/paper/9547-can-you-trust-your-models-uncertainty-evaluating-predictive-uncertainty-under-dataset-shift>
22. E. Hüllermeier, S. Destercke, and M. H. Shaker, “Quantification of Credal Uncertainty in Machine Learning,” *UAI*, 2022.
    <https://proceedings.mlr.press/v180/hullermeier22a.html>
23. A. N. Angelopoulos and S. Bates, “A Gentle Introduction to Conformal Prediction and Distribution-Free Uncertainty Quantification,” 2021.
    <https://arxiv.org/abs/2107.07511>

---

# 17. Core Maxim

> **Intelligence emerges not from a single model possessing every capability, but from coordinated cognitive processes operating over shared, persistent,
> verifiable and uncertainty-aware representations of knowledge, goals, evidence, memory, time, and action.**
