# GCAS — General Cognitive Architecture Specification

## GCAS 0.1 — Architectural Foundations (Refined Draft)

**Status:** Draft / Specification Proposal
**Version:** 0.1
**Scope:** Language- and implementation-independent cognitive architecture for persistent, hybrid neuro-symbolic intelligent systems.

---

## 0. Abstract

GCAS defines an abstract, implementation-independent architecture for persistent artificial cognitive systems capable of reasoning,
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

GCAS specifies cognitive objects, interfaces, information flows, invariants, and behavioral requirements rather than programming languages,
storage engines, neural architectures, or proprietary frameworks.

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
* **G8. Explicit Uncertainty & Time:** Represent uncertainty, confidence, contradiction, and temporal validity intervals explicitly.
* **G9. Metacognition:** Support reasoning about system performance, resource usage, progress, and failure modes.
* **G10. Evolvability:** Enable modular replacement and upgrade of cognitive processors without architecture redesign.

## 1.2 Non-Goals

GCAS does NOT specify:
* A programming language or specific compiler,
* A specific LLM architecture or neural model weights,
* A specific database or storage engine,
* A specific formal logic system,
* An operating system or container runtime,
* Consciousness, subjective experience, or qualia,
* A claim that compliant systems are sentient.

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

## 2.7 Design Maxim

A compliant system MUST make the following distinctions explicit at every level:
```
what the system generated
what the system believes
what the system observed
what the system can prove
what the system can reproduce
what the system believes to be valid at time T
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
* **Confidence:** Numerical or qualitative measure of reliability $[0.0, 1.0]$.
* **Timestamp & Temporal Validity:** Creation time and temporal validity interval (`valid_from`, `valid_to`, `invalidated_by`).
* **Relations / Dependencies:** Graph links to supporting, parent, or contradicting COs.
* **Scope & Lifecycle Metadata:** Validity boundaries, expiration, or status flags.

## 3.2 Three-Axis Epistemic Model

To prevent semantic conflation, GCAS separates epistemic classification into three independent axes:

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
confidence:          0.82
temporal-validity:   [2026-01-15, INF]
```

### Epistemic Classification Rules
1. **Observation ≠ Fact:** Information received from sensors or user input is an `Observation` with provenance `SENSOR` or `USER`.
   It MUST NOT automatically be classified as `VERIFIED` or `ACCEPTED` without verification (e.g. faulty sensor or unverified user claim).
2. **LLM Output = Hypothesis:** Content generated by neural models MUST carry provenance `LLM` and initial epistemic status `HYPOTHESIS`.
3. **Fact Definition:** A **Fact** is defined strictly as a Claim with epistemic status `ACCEPTED` and verification status `VERIFIED` or `FORMALLY_VERIFIED`.

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
3. **Belief:** A Claim currently accepted by the system with explicit confidence and provenance. Contradictory beliefs MAY temporarily coexist.
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

Candidates compete based on:
* Goal relevance,
* Novelty and surprise,
* Urgency,
* Uncertainty / conflict level,
* Expected information gain,
* Risk and safety significance.

## 4.3 Workspace Broadcast

Once admitted, a Cognitive Object is broadcast to participating processors.

> **Broadcast ≠ Synchronous Function Call**

Broadcasting makes information available; processors independently determine whether to react. Processing MAY be event-driven and asynchronous.

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
WorkspaceBroadcast     GoalCompleted
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

**J-space** is recognized as one possible neural workspace implementation or source adapter for NCSI.

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
* **Controlled Forgetting:** Retention MUST be governed by relevance, confidence, utility, and decay policies. Forgetting, compression,
  summarization, supersession, and archival are essential system features.

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

## 9.2 Environment Model & Reproducible Actions

Systems SHOULD maintain an explicit model of environment state, distinguishing `believed state` from `freshly observed state`.

Actions SHOULD generate **Reproducibility Records** containing:
```
input payload | code executed | environment hash | dependencies | parameters | output hashes | provenance
```

## 9.3 Scientific Reasoning Cycle

GCAS natively supports explicit scientific reasoning:
```
Question ──> Hypothesis ──> Prediction ──> Experiment ──> Observation ──> Evidence ──> Evaluation ──> Belief Update
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

## 11.1 Cognitive Invariants (I1–I10)

A compliant GCAS implementation MUST satisfy the following invariants:

* **I1:** Generated content is candidate cognition (`HYPOTHESIS`), NOT automatic knowledge.
* **I2:** Persistent knowledge MUST carry provenance and verification metadata.
* **I3:** Uncertainty, confidence, and temporal validity MUST remain explicitly representable.
* **I4:** Contradictory claims MUST NOT silently overwrite one another.
* **I5:** External state MUST be observed from the environment when accessible, not inferred purely from internal memory.
* **I6:** Actions MUST produce observable, auditable results.
* **I7:** Key derivations and execution results SHOULD be reproducible where environment permits.
* **I8:** Failure (`UNKNOWN`, `FAILED`) MUST remain an acceptable and preferred outcome over fabricated certainty.
* **I9:** Persistent memory MUST NOT depend solely on LLM context windows.
* **I10:** No individual cognitive processor is assumed infallible.

## 11.2 Minimal Conformance Requirements (GCAS-Core)

To claim **GCAS-Core** compliance, a system MUST implement at minimum:
1. Explicit Cognitive Objects with metadata, 3-axis epistemic model, and provenance,
2. Epistemic distinction between generated hypotheses and verified beliefs,
3. Bounded Global Workspace process with selective admission/broadcast,
4. At least two distinct specialized cognitive processors (Generative + Deliberative),
5. Explicit memory architecture separate from conversation prompt history,
6. Recurrent cognitive cycle with progress and loop monitoring,
7. Separated execution runtime with auditable Action/Result semantics,
8. Explicit representation of uncertainty, temporal validity, and failure states.

A system does NOT require a specific neural model, J-space, Scheme, Lean, or Guix to achieve GCAS-Core conformance.

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

---

# 13. Roadmap: GCAS 0.2 — Cognitive Process & Operational Semantics

GCAS 0.1 establishes the normative ontology, invariants, and architectural components. **GCAS 0.2** will formalize
the **Operational Semantics** ("How cognition proceeds") by defining state transitions, event triggers,
and CO lifecycles over an explicit scientific inquiry dry-run.

## 13.1 Benchmark Inquiry Dry-Run Cycle

GCAS 0.2 will formalize exact operational semantics across the following 14-stage execution sequence for the target query *"Is claim X from publication Y true?"*:

```text
User Question
      ↓
Question CO
      ↓
Goal CO
      ↓
Workspace activation
      ↓
Memory retrieval
      ↓
Generative Hypothesis (LLM)
      ↓
Evidence retrieval
      ↓
Competition
      ↓
Deliberative / Symbolic Verification
      ↓
Conflict / Confirmation Evaluation
      ↓
Belief Update
      ↓
Reflection
      ↓
Answer Generation
```

For each transition step, GCAS 0.2 will specify:
1. Created/modified Cognitive Objects,
2. Originating cognitive processor,
3. Workspace admission criteria,
4. Broadcast trigger conditions,
5. Epistemic state mutation rules,
6. Provenance graph update semantics,
7. Termination and loop-interruption criteria.

---

# 14. Open Research Questions (GCAS 0.2 Candidate Topics)

1. **Workspace Capacity:** How should workspace capacity bounds be mathematically or empirically defined?
2. **Standardized Competition:** Can workspace competition algorithms be standardized across heterogeneous processors?
3. **Identity & Deduplication:** What are the optimal graph deduplication algorithms for Cognitive Objects across long time spans?
4. **Heterogeneous Confidence:** How can confidence metrics from neural, probabilistic, and symbolic systems be unified?
5. **Formal Contradiction Models:** What paraconsistent logic models best represent coexisting contradictory beliefs?
6. **Decay & Retention Curves:** What memory decay algorithms optimize retention vs. computational efficiency in persistent AI?
7. **Attention Granularity:** Should attention be implemented as an explicit central processor, a distributed field, or both?
8. **NCSI Standardization:** What is the minimal universal API for exposing internal neural representations across diverse model architectures?
9. **Symbol Grounding:** How can continuous neural concept directions be aligned with discrete symbolic atoms without false equivalences?
10. **Neural Steering Invariants:** How can activation steering be constrained to prevent degradation of model instruction-following?
11. **Self-Model Architecture:** What minimal explicit self-model is required for robust metacognition?
12. **Goal Provenance & Motivation:** What safety policies should govern goal creation, modification, and suspension?
13. **Bus Transactional Guarantees:** Does the Cognitive Bus require causal ordering, transactional rollback, or vector clocks?
14. **Resource-Aware Attention:** How can monetary cost, token budgets, and hardware latency participate directly in cognitive attention algorithms?
15. **Execution Semantics & Dry Run:** Formalizing the step-by-step cognitive execution graph for a complex scientific benchmark task ("How cognition proceeds").

---

# 15. Core Maxim

> **Intelligence emerges not from a single model possessing every capability, but from coordinated cognitive processes operating over shared, persistent,
> verifiable representations of knowledge, goals, evidence, memory, time, and action.**
