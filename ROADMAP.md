# GAIA Roadmap

> *Last updated: 2026-08-27*
>
> This document tracks the development plan for the GAIA (GNU AI Assistant) project.
> For an introduction to the project, see [README.md](README.md).

---

## Current State Summary

GAIA has a functional legacy RLM-style investigation loop, persistent Guile REPL environment, safety validation,
trajectory logging, and LiteLLM integration. It also has a substantial GCAS substrate: Cognitive Objects, durable
state and events, a bounded Workspace implementation, Control primitives, structured memory, and auditable
Action/Result execution. Production `solve` is assembled from Bus-attached processors with a per-Goal lifecycle, explicit
Workspace rounds, bounded replanning after failed actions or conflicts, and an independent Goal-verification boundary. The minimal
GCAS-Core 0.2 conformance gate now covers failure-first replanning, persistence, budgets, interruption, and both supported clients.
This establishes the architecture, not broad task competence: the production verifier registry currently contains a deterministic
Fibonacci contract, while unknown natural-language task classes fail closed as `INCONCLUSIVE`.
The immediate product milestone is now the **GAIA MVP — Persistent Verified Assistant**: every `solve` must terminate at the
client boundary, verified memory and its justification graph must survive restarts without transcript replay, contradictions
must remain explicit, repair behavior must be measurable, and a small set of task classes must have executable acceptance
contracts. The normative MVP contract and acceptance scenarios are maintained in [docs/gaia-mvp.md](docs/gaia-mvp.md).

**Architecture:** Rust Client - GAIA Server (Guile REPL) - LiteLLM Proxy - LLM backends (Ollama, Lemonade, external LLM API etc.)

---

## System Architecture: Kernel + Modules

GAIA is organized as a **self-contained kernel** with **pluggable extension modules**.
The kernel is being migrated toward a complete, self-improving neuro-symbolic AI loop.
Modules extend its capabilities into specific domains without modifying the core.

```
┌─────────────────────────────────────────────────────────┐
│                   Extension Modules                     │
│ ┌───────────┐ ┌──────────┐ ┌───────────┐ ┌───────────┐ │
│ │ gaia-proof│ │ gaia-sci │ │ gaia-accel│ │ gaia-os   │ │
│ │ Lean4, Z3 │ │ RAG,     │ │ MLIR/IREE │ │ Shepherd, │ │
│ │ Theorem   │ │ Hyperon, │ │ Tensor    │ │ Guix      │ │
│ │ Proving   │ │ Literate │ │ Compile   │ │ Containers│ │
│ └─────┬─────┘ └────┬─────┘ └─────┬─────┘ └─────┬─────┘ │
│ ┌─────┴──┐ ┌───────┴──┐ ┌───────┴──────┐       │       │
│ │gaia-io │ │gaia-     │ │gaia-desktop  │       │       │
│ │Voice,  │ │desktop   │ │COSMIC, GNOME,│       │       │
│ │Vision  │ │Emacs,IDE │ │Wayland       │       │       │
│ └────┬───┘ └────┬─────┘ └──────┬───────┘       │       │
├──────┴──────────┴──────────────┴───────────────┴───────┤
│                    GAIA KERNEL                          │
│  GCAS-Core migration → Memory → Learning & Evolution    │
│                                                         │
│  Cognitive State + Workspace + Control + REPL +         │
│  DSL ($gscm$) + DPO/Elo Curation + Champion/Challenger  │
├─────────────────────────────────────────────────────────┤
│                    Foundation                           │
│  GNU Guile + Goblins + GNU Guix + LiteLLM + Rust CLI   │
└─────────────────────────────────────────────────────────┘
```

---

# ═══ GCAS-CORE MIGRATION ═══

GCAS is GAIA's normative architectural source of truth. The goal is a **working, persistent neuro-symbolic cognitive system**
that coordinates specialized processors through explicit state, workspace competition, control, memory, and auditable execution.
The legacy RLM loop is retained only as a compatibility and long-context investigation capability.

## GCAS-Core 0.2 Baseline — Completed

- [x] **Cognitive Object Model** — Validated COs carry provenance, epistemic and verification statuses, temporal validity, confidence, and relations.
- [x] **Session Cognitive State** — Each server session owns durable CO state and an event log. Action outcomes receive linked reproducibility observations.
- [x] **Bounded Global Workspace** — Capacity, proposal metadata, scoring, explicit competition rounds, selective admission, broadcast, and release of the active focus are implemented. Durable COs remain in Cognitive State after their Workspace focus ends.
- [x] **Cognitive Process and Control lifecycle** — Each `solve` owns an explicit Goal process, completion criteria, isolated Control budgets, exactly-once terminal state, interruption cleanup, and rejection of late callbacks.
- [x] **Production processor assembly** — Memory Retrieval, Generative, Planner, Execution, Deliberative, Answer, and Control processors are attached to the Cognitive Bus. The server orchestrator now supplies only LLM/sandbox/client adapters and session history persistence for `solve`.
- [x] **Execution boundary** — Default `solve` and direct REPL cross explicit Action → Result/Failure boundaries with auditable links and reproduction observations. Richer capability policy remains post-Core hardening.
- [x] **Memory and context reconstruction** — Durable structured memory is separate from transcripts. Verified Result/Evidence/Claim chains and explicit user testimony are consolidated, goal-relevant facts are retrieved across turns, and prompts are reconstructed from typed GCAS sources. Semantic retrieval and richer memory roles remain post-Core work.
- [x] **Recurrent cognitive cycle** — Production `solve` represents `Plan` COs and routes failed actions and conflicts through `Reflection` into bounded Generative replanning. Execution claims are then submitted to a separate Goal verifier.
- [x] **Goal-specific verification and Answer Processor** — An injected verifier returns an explicit verdict. Only an accepted, verified Claim that satisfies the active Goal may emit `GoalCompleted`; the default policy is `INCONCLUSIVE` without task-specific verification.
- [x] **Operational vertical acceptance test** — A deterministic failure-first Fibonacci test rejects an initial bad Action, feeds the conflict through replanning, accepts a revised Action through an independent oracle, and terminates with exactly one `GoalCompleted`.
- [x] **Client observability and conformance gate** — CLI and Emacs expose the event trace and Cognitive State view. Automated tests cover accepted-answer policy, restoration, Control budgets, interruption/late callbacks, failure-first repair, and both clients. Control-driven termination now invokes the client completion callback exactly once; three failed REPL Actions regress through the server adapter to a terminal `(final ...)` response instead of leaving the CLI waiting.

The detailed gap analysis and conformance gate are maintained in [docs/gcas-core-conformance.md](docs/gcas-core-conformance.md).

## GCAS 0.3 Uncertainty Framework — Migration Priority

The GCAS 0.3 specification makes uncertainty a versioned cognitive state and distinguishes correctness, verification, and confidence.
The existing scalar CO `confidence` and Workspace `uncertainty` fields are not calibrated posterior probabilities and MUST remain labeled
as scheduling or legacy compatibility metadata until migrated.

- [x] **UncertaintyAssessment CO and graph schema (P0)** — Machine-validated assessment, calculus, correctness-observation, and calibration COs carry target, quantity, representation, typed sources, conditioning, lineage/dependence, method/diagnostics, version links, scope, provenance, and validity without overwriting historical values.
- [x] **Rebuildable uncertainty projection `U` and Bayesian updater (P0)** — `U` is rebuilt deterministically from ordinary Cognitive State COs and relations. The exact Beta–Bernoulli slice records explicit priors, Bernoulli assumptions, prior/posterior predictive checks, exact-inference diagnostics, sensitivity, and immutable update links.
- [x] **Correctness feedback and calibration records (P0)** — Later correctness observations link to the exact forecast assessment. Calibration records retain assessment IDs, samples, Brier score, log loss, curve bins, sharpness, coverage/decision-loss applicability, sample count, and detected scope shift.
- [x] **Uncertainty propagation and dependence control (P1)** — Assessment dependencies and source lineage are explicit, invalidation propagates through conditioning/update chains, and processor outputs record either a `quantified-by` dependency or `NO_APPLICABLE_ASSESSMENT`. Cross-calculus numeric combination fails closed.
- [x] **Uncertainty-aware Control policy (P1)** — Control separately exposes urgency, risk, conflict, out-of-domain state, expected information gain, cost, relevance, and priority. Goal-scoped decisions support acceptance, abstention, escalation, and evidence acquisition; no universal threshold is introduced.
- [x] **Legacy scalar migration (P1)** — Historical CO `confidence` and Workspace `uncertainty` remain validated legacy/scheduling metadata and acquire no posterior semantics. Restored legacy sessions create no synthetic assessments; neural invariants remain unchanged.
- [x] **GCAS-Uncertainty 0.3 conformance gate (P1)** — `tests/test-uncertainty.scm` covers malformed schemas, legacy restoration, normative Beta–Bernoulli values, restart/rebuild, supersession/invalidation, immutable correctness/calibration, scope shift, abstention/escalation, Control competition, and cross-calculus non-combinability. Reports distinguish `GCAS-Uncertainty 0.3` from the narrow `GCAS-Bayesian 0.3 / BETA_BERNOULLI` profile.

The implementation order and acceptance criteria are defined as U0–U4 in
[the GAIA MVP contract](docs/gaia-mvp.md#gcas-03-implementation-plan). The first
implementation slice remains the graph-memory foundation and documentation
alignment; it does not itself claim GCAS 0.3 uncertainty conformance.

### Operational completion sequence

1. **[Completed] Cognitive Process lifecycle** — Introduce a process object containing Goal,
   completion criteria, per-process budgets, progress state, and one terminal outcome.
2. **[Completed] Event-driven processor assembly** — Attach Planner, Memory Retrieval,
   Generative, Execution, Deliberative, and Answer processors to the session Bus.
   Reduce the session orchestrator to lifecycle and client transport duties.
3. **[Completed] Workspace scheduling rounds** — Collect proposals before admission, perform
   real competition, broadcast the winner, and release or supersede processed COs.
4. **[Completed] Planning and feedback recurrence** — Represent `Plan` COs and linked subgoals as `Goal` COs, then route
   Result, Failure, Conflict, and Reflection back into planning or generation.
5. **[Completed] Goal verification** — Deterministic verifier contracts ensure that
   execution success alone never satisfies a Goal.
6. **[Completed] Answer policy and client observability** — Complete client-facing process,
   Goal, Workspace, CO, and terminal-rationale views; retain the policy that raw
   LLM output is never presented as the system answer.
7. **[Completed at Core minimum] Memory consolidation** — Store verified evidence and claims,
   preserve their provenance graph, persist explicit user testimony, and retrieve structured facts across turns.
8. **[Completed] Conformance acceptance** — Pass the failure-first vertical test plus restart,
   budget, interruption, and both-client protocol tests before claiming the GCAS-Core 0.2 baseline.

The next implementation phase expands the verifier registry and planner beyond
the reference Fibonacci capability, adds semantic/conflict-aware memory, and
strengthens capability policy. GCAS 0.3 additionally changes the architectural
boundary through the uncertainty-state migration defined above.

## GAIA MVP — Persistent Verified Assistant

Full GCAS expansion is not a prerequisite for a useful GAIA, but persistent
cognitive memory is part of the MVP rather than a later product extension. The
milestone combines a narrow dependable `solve` path with durable graph memory,
guarded retrieval, contradiction preservation, and multi-session evaluation.
The small local model currently used by default (`gemma4:e2b`) is tuned primarily
for tool use rather than sustained Guile REPL programming. GCAS must expose model
limitations honestly and compensate with structure; architectural conformance
alone is not evidence of task competence or cognitive continuity.

- [x] **MVP definition and acceptance contract (P0)** — `docs/gaia-mvp.md` defines the product claim, required invariants, six longitudinal acceptance scenarios, delivery milestones, and explicit post-MVP scope.
- [x] **Cognitive Memory Graph v1 (P0)** — The local durable store exposes typed duplicate-safe links, bounded graph traversal, dependency discovery, transitive invalidation, versioned supersession, explicit episodic/semantic/procedural/user-testimony/metacognitive roles, and a bounded lazy STI projection. Invalidated, expired, and superseded Claims are ineligible as current facts. The public memory interface remains the adapter boundary; a Goblins/AtomSpace backend is an implementation replacement rather than an MVP acceptance dependency.
- [x] **Verified cross-session graph-memory gate (P0)** — A deterministic test stores a verified Evidence/Claim chain, creates a fresh session, resolves its justification edge, retrieves the Claim for a new Goal, and reconstructs context without transcript replay. The same gate covers transitive dependency invalidation and auditable supersession.
- [x] **Consolidation and guarded graph retrieval (P0)** — Governed consolidation runs at every production terminal boundary, records memory role, retention reason, and revalidation policy, and retains a verified procedure after successful Goal verification. Retrieval is bounded and ranks by Goal content, graph neighborhood, temporal validity, provenance, contradiction/supersession state, memory role, and STI activation without epistemic promotion.
- [x] **Longitudinal memory corpus (P0)** — Deterministic restart gates cover unverified user testimony, verified graph memory, contradiction-driven transitive invalidation and successor revision, procedural reuse, stale-memory rejection, and versioned metacognitive capability assessment after successive outcomes. Repeated live-model cases remain part of the M5 readiness gate.

- [x] **Terminal delivery invariant (P0)** — Every active production process reaches one durable terminal event and invokes `on-finished` exactly once. Failure-budget, transition-budget, no-progress, and user-interrupt outcomes all reach the client. An interrupt with no active process does not create an orphan `ProcessTerminated` event.
- [x] **Three-failure regression (P0)** — Deterministic processor and server-adapter tests execute three distinct failing Actions, assert `FAILURE_BUDGET_EXHAUSTED`, one `ProcessTerminated`, one completion callback, and a terminal `(final ...)` protocol message.
- [x] **Small deterministic evaluation corpus (P0)** — `make gcas-eval` runs 23 model-free fixtures through the production processor: first-pass success, preflight/syntax/runtime/verifier repair, incorrect and repeated Actions, missing Actions, unavailable verifiers, all Control budgets, interruption, and late callbacks. It gates exact outcomes, model/execution attempts, one terminal event/callback, hangs, false completion, repair success, and reports latency. The current baseline is 23/23, zero hangs, zero false completions, and 5/5 successful repair paths.
- [/] **Model-agnostic live evaluation matrix (P0)** — `make gcas-live-eval` runs a shared five-task verifier-backed corpus across configurable OpenAI-compatible models, repetitions, thinking modes, endpoints, and prompt overrides. It reports every run plus model/task cells, first-pass and repair success, lifecycle failures, calls, executions, latency, and token usage when supplied by the endpoint. Remaining work: establish a repeated `gemma4:e2b` baseline, add prompt-variant comparison, and set readiness thresholds per advertised capability.
- [x] **Phase-aware cognitive prompt projection (P1)** — Production `solve` uses a compact GCAS-only Action contract without legacy `FINAL/CONFIDENCE`, while `/investigate` retains the RLM prompt. Initial and repair projections keep chat history empty and include typed phase, capability/action schema, remaining transition/stall/failure/replan budgets, exact error class and failing form, Goal, Workspace, Memory, and Reflection state.
- [x] **Structured repair policy (P1)** — Scheme and Wisp Actions are parsed and macro-expanded without evaluation before an Action CO or execution request is created. Reader and macro syntax failures name the rejected form, feed bounded replanning, require a complete distinct replacement, and preserve non-progress detection.
- [x] **Capability/verifier registry (P1)** — Five advertised evaluation capabilities have versioned manifests, intent matchers, Goal contracts, Action schemas, and deterministic verifiers. Reusable verifier classes cover exact/structured values, predicate/property, unit-test, artifact, environment-state, and scoped human approval. Unknown and ambiguous task classes fail closed; LLM judgments cannot independently confer `VERIFIED`.
- [ ] **Readiness gate (P1)** — Claim general assistant usefulness only after the evaluation corpus has zero hangs and false completions, bounded interruption latency, and an explicitly reported success rate for every advertised capability.

The prompting design is documented in
[docs/gcas-prompt-projection.md](docs/gcas-prompt-projection.md), and the corpus
scope and extension rules in [docs/gcas-evaluation.md](docs/gcas-evaluation.md).
The exact candidate capabilities and release thresholds are published in
[docs/capability-matrix.md](docs/capability-matrix.md).
The complete MVP product, memory contract, and GCAS 0.3 implementation plan are documented in
[docs/gaia-mvp.md](docs/gaia-mvp.md).
The read-only NCSI/J-space adapter is now implemented as an opt-in experimental
profile and is not a blocker for this milestone. Its M5 pilot establishes
transport, epistemic, fallback, stability, and overhead behavior; it does not
establish task benefit or causal utility. Textual prompt projection remains the
production baseline and fallback. The cross-project architecture, ownership
boundaries, acceptance gates, and canonical milestone checklist are maintained in
[docs/ncsi-jlens-integration.md](docs/ncsi-jlens-integration.md).

### Legacy RLM status

The existing `rlm-loop` is a useful multi-step LLM–REPL feedback implementation, not the GCAS cognitive loop and not yet a full implementation of the RLM paper's recursive long-context decomposition. Freeze it as `legacy-repl-investigation-loop` behavior while GCAS-Core is introduced. Later, expose it as an optional Investigation Processor for large-data tasks.

---

## Legacy foundation — retained capabilities

Core infrastructure that is already built and working.

- [x] **Legacy RLM investigation loop** — Multi-step LLM–REPL feedback with code extraction, execution, and feedback; retained behind the GCAS execution boundary.
- [x] **Persistent REPL Environment** — Variables and functions survive across RLM steps within a task
- [x] **Static Safety Validator** — AST-level recursive scan for banned primitives (`system*`, `delete-file`, etc.)
- [x] **Module-based Sandbox** — Whitelisted imports for AI-generated code
- [x] **FINAL/CONFIDENCE Signals** — Structured completion and confidence extraction
- [x] **Structured Error Handling** — Syntax, permission, and runtime error classification with feedback
- [x] **LiteLLM Integration** — OpenAI-compatible API client replacing the legacy RAI server
- [x] **Trajectory Logging & Curation** — Every interaction logged to timestamped `.jsonl` files, split into success/failure datasets via `curator.scm` | *→ K3: Self-Training Loop*
- [x] **Thinking Mode** — Native `<|think|>` tag support for Gemma 4 reasoning
- [x] **Live Monitor** — `make monitor` for real-time trajectory viewing
- [x] **Benchmark Suite** — Needle-in-a-Haystack (NIAH) benchmark for RLM validation | *→ Showcase Benchmark*
- [x] **System Tools** — File ops, grep, sed, awk, journalctl wrappers with flexible arguments in `tools.scm` | *→ gaia-os*
- [x] **Parenthesis Analyzer & Auto-healing** — Mismatched parens auto-repair and escape sequence healing in `sandbox.scm`
- [x] **Last-block Extraction** — Prefers last code block in LLM response
- [x] **Auto LiteLLM Server** — `./bin/gaia-server` starts LiteLLM if it is not running; the deprecated `make run` target intentionally exits with guidance.
- [x] **Conversation continuity boundary** — Session transcripts remain an audit/UI record and `/clear` establishes a fresh boundary. `solve` reconstructs context from structured memory instead of replaying the transcript; explicit user testimony and verified evidence chains persist across turns. General conversational summarization remains post-Core memory work.
- [x] **Native CLI Client (Rust)** — Build a fast, native terminal client using the "scrollback" REPL model with `rustyline` | *→ gaia-desktop*
- [x] **S-expression Protocol over UNIX Sockets** — S-expression communication socket layer parsed in Rust via `lexpr`
- [x] **Human-in-the-Loop (HITL) Sandbox** — Interactive permission system in the Rust client to intercept risky AST-detected operations

---

## Hardening & stabilization

Hardening the agentic loop to handle syntax constraints of smaller local models (e.g. 3B `gemma4:e2b`) and decoupling the client/server layout.

- [x] **Wisp (SRFI-119) Integration** — Implement the whitespace-to-Lisp parser in the execution pipeline. This allows LLMs to write Scheme code using Python-like indentation, solving the "parenthesis blindness" of small models while retaining Guile's AST-level safety and homoiconicity.
- [x] **Client-Server Refactoring (De-bloat gaia-cli)** — Fully delegate slash command routing to the server and remove local output parsing (e.g. `/help` text definitions, and alist formatting). Client should become a presentation-agnostic renderer of pre-parsed events. | *→ gaia-desktop*
- [x] **Advanced Terminal UX & Inline Status** — Non-blocking inline spinner or bottom status bar showing current background RLM execution state using ANSI cursor control codes or `indicatif`. | *→ gaia-desktop*
- [x] **Expanded Auto-healing** — Programmatic unmatched parens closing and syntax self-repair hardening before running `eval`.
- [x] **Modularize Actors Framework** — Split the monolithic `actors.scm` into separate files (`sandbox-actor.scm`, `agent-actor.scm`, `session-orchestrator.scm`) to separate session orchestration, environment evaluation, and agent cognitive logic.
- [/] **HITL Security Hardening (Command Injection)** — Replace simple prefix checks in `run-command` with shell-token parsing or direct executable invocation (`system*`) to prevent shell injection bypasses (e.g., `grep; rm -rf /`). *(Partially completed: basic safety checks checking for forbidden characters `#\; #\& #\| #\` #\$` are implemented, but shell-token parsing / direct system* execution is pending).*
- [x] **Efficient HITL Sync** — Replace busy-waiting `usleep` polling in `permission-sink` with Guile mutexes and condition variables.
- [x] **HITL Metadata Exchange** — Define an S-expression metadata format for permission requests so the client doesn't need to parse Scheme AST to print file diffs.
- [/] **HITL Permission Scoping** — Introduce session/directory scoping in client approvals to reduce prompt fatigue (e.g., "Allow all write-file commands in this path"). *(Partially completed: server-side matching scopes via directory/always rules are implemented, but client UI integration is pending).* | *→ gaia-desktop*
- [x] **Bailout Mechanism** — If confidence drops drastically or the error loop persists too long, pause the main loop and spawn a diagnostic sub-agent.
- [x] **High-level Standard Library for LLM** — Add ready-made higher-order procedures to `tools.scm` to offload the model from writing complex nested loops:
  - `(read-files '("A" "B"))` — batch file reading
  - `(patch-file path old-string new-string)` — in-place string replacement in files
  - `(map-files dir pattern proc)` — apply procedure to matching files
- [ ] **Code Instrumentation & Auto-Logging** — Automatically rewrite LLM-generated code to wrap function calls in error handlers. | *→ K3: AST-based Training*
- [ ] **Auto-Scaffolding** — On agent startup in a directory, silently run a lightweight `(list-files)` and inject the directory map into the system prompt for immediate spatial awareness.
- [ ] **Deterministic Replay** — Replay saved trajectory files offline without API costs for debugging and demonstration purposes. | *→ Showcase Benchmark*
- [ ] **Prompt Caching Optimization (Encoder-Decoder Analogy)** — Optimize the RLM loop to cache large base context trees (loaded modules, file structure, system config) read-only, sending only incremental steps and errors to minimize token costs and latency. | *→ K3: Matchmaker Task Scheduler*

---

## GCAS memory, workspace & deliberation

*Moved from former Phase 7 to address context rot and context window clogging.*

- [/] **Atoms as Goblins Actors** — The GAIA MVP now treats AtomSpace semantics as a product requirement: durable CO nodes, typed graph edges, traversal, dependency invalidation, and supersession are implemented over the transparent local store. Remaining work is the Goblins actor backend, transactional graph updates, spreading activation, and bounded active relevance context (up to ~1000 nodes). Storage remains replaceable and MUST preserve the contracts in [docs/gaia-mvp.md](docs/gaia-mvp.md). | *→ gaia-sci: Hyperon FFI, gaia-proof: Goal Caching*
- [ ] **STI/LTI Memory** — Implement Short-Term Importance (STI) and Long-Term Importance (LTI) weights for memory candidates. Decimate STI asynchronously after cognitive process transitions. | *→ gaia-sci: Cognitive State Serialization*
- [/] **NCSI/J-space Integration Program** — The versioned contract (M0), GAIA production HTTP/NDJSON-over-UDS adapter and bounded JSPACE policy (M4), and comparative pilot with an explicit `SHIP_EXPERIMENTAL` decision (M5) are complete. RAI's M1–M3 lifecycle, artifact-reproduction, resource-baseline, authentication, and failure-path gates remain partially open. Read-only neural observations precede any steering capability; signals remain observations and cannot directly confer `VERIFIED` or `ACCEPTED`. Detailed status is tracked only in the [canonical integration plan](docs/ncsi-jlens-integration.md), and the published evidence is in [the M5 report](docs/evaluations/ncsi-smollm2-m5.md).
  - **J-space to AtomSpace Mapping (M7)** — After AtomSpace and STI/LTI exist, evaluate whether J-lens activations can improve symbolic-node importance over simpler textual or symbolic controls. | *→ gaia-proof: J-space Guided Theorem Proving*
  - **J-lens Activation Injection (M6)** — After the read-only adapter passes comparative evaluation, evaluate bounded steering/patching of symbolic states and REPL errors with explicit Control policy, causal controls, audit, and fallback. | *→ K3: CRT, gaia-proof: J-space Guided Theorem Proving*
- [/] **Context Reconstruction** — Production `solve` reconstructs a prompt from the current goal, admitted Workspace COs, lexically selected structured memories, and active constraints without appending the transcript. Richer retrieval and evidence/claim consolidation remain.
- [ ] **G-Expressions ("Context Teleportation")** — Use GNU Guix's G-expressions (`#~`) to serialize variable contexts and modules when spawning sub-agents. | *→ gaia-os: Guix Containers, gaia-sci: Cognitive State Serialization*
- [ ] **Governed self-modification** — Route proposals to modify procedures, policies, models, or architecture through the GCAS proposal, sandbox, verification, approval, deployment, and rollback pipeline. | *→ Learning & evolution*
- [ ] **AND/OR Tree State Orchestration** — Refactor session orchestration to track nested tasks in a tree format (delegations as AND nodes; alternative execution pathways as OR nodes), enabling backpropagation of goal success/failure and clean transactional rollbacks. | *→ gaia-proof: Global Goal Caching*

---

## K3 — Self-Training Loop & Safe DSL (`make learn`)

*The kernel's culmination: a closed loop of use → verification → curation → training → evaluation → deployment. Includes the $gscm$ DSL as an integral safety and type-verification layer for the training pipeline.*

### DSL & Type Safety

- [ ] **Embedded DSL via Guile Macros ($gscm$)** — Custom syntax macros using `syntax-case` to define a safe sub-language ($gscm$) that automatically enforces type ontologies and physical dimension units. Serves as GAIA's equivalent of MeTTa (OpenCog Hyperon) — a domain-specific language for safe, typed neuro-symbolic computation. | *→ gaia-accel: MLIR compilation target*
- [ ] **J-space Type Constraint Verification** — Use the J-lens to verify if internal continuous representations in the model's global workspace align with the symbolic type constraints of the `$gscm` DSL *prior* to token generation. Halt generation or apply J-space patching if dimensional or ontological mismatches (e.g. meter vs. second) are detected in flight. | *→ gaia-proof: Cycle-Consistency*

### Dataset Curation

- [ ] **DPO/ORPO Dataset Curation** — Refactor `curator.scm`. If code generated by LLM causes syntax errors but gets repaired via auto-healing or subsequent steps, output a comparison pair: `[Broken Code = Rejected]` and `[Healed/Fixed Code = Chosen]`.
- [ ] **Trajectory Cleaning (Compact Logging)** — Modify `curator.scm` to strip dead-end attempts before writing to `.jsonl`. Address the auto-healing issue by rewriting history for Ideal SFT.
- [ ] **AST-based Training (Code-as-Data)** — Instead of logging textual code corrections, log the evolution of AST structure to show how the model improved logic step-by-step. | *→ gaia-proof: Formal Verification Bridges*
- [ ] **Elo-Based Dataset Matchmaking** — Integrate pairwise rating agents in `curator.scm` using Plackett-Luce strength optimization to construct Elo rankings of trajectories, identifying the highest quality DPO/ORPO training candidates.

### Training & Alignment

- [ ] **Counterfactual Reflection Training (CRT)** — Implement a training pipeline using J-space alignment. Train the model to generate self-reflection tokens if interrupted mid-task, shaping the J-space internally with safety and alignment concepts (e.g. `integrity`, `honest`, `failure`), and improving task robustness during autonomous evaluations.
- [ ] **External GPU Training Node** — Script `make learn` to upload dataset to external node using QLoRA/Unsloth (e.g. for adapter fine-tuning).

### Evaluation & Evolution

- [ ] **Champion/Challenger System** — After training a new adapter: run benchmark -> compare with current model -> promote if better. | *→ Showcase Benchmark*
- [ ] **Automatic Hot-Swap** — Detect newly trained adapter and hot-reload LiteLLM configuration without interrupting current sessions.
- [ ] **Matchmaker Task Scheduler** — Implement a task scheduler that weights synthetic training targets based on task variance or failure rate, focusing computational resources on hard/undecided problems.
- [ ] **Evolutive Variant Generation** — Create programmatic and LLM-steered variants of training tasks (via simplification, generalization, and analogy prompting) to construct a diverse, curriculum-style local training set. | *→ gaia-proof: Cycle-Consistency*

---

# ═══ SHOWCASE BENCHMARK ═══

*Validation suite to demonstrate the kernel's value. Used by the Champion/Challenger system (K3) to evaluate model improvements and by the Matchmaker (K3) to identify weak areas.*

## GAIA-SysOps — GNU/Linux System Administration

100 tasks covering Guix package management, Shepherd service configuration, log analysis, network diagnostics, and system recovery. Designed to test the full RLM loop on GAIA's home domain.

- **Metric:** % tasks solved correctly, mean RLM steps, token budget consumed
- **Comparison baseline:** Same tasks solved via GAIA with external LLM API (Gemini, Claude) to measure the gap between local and frontier models and track self-training progress

## GAIA-Math — Mathematical & Programming Challenges

50 tasks covering symbolic algebra, combinatorics, number theory, and algorithmic problems with formally verifiable solutions. Designed to validate the self-training loop and prepare for formal verification (→ *gaia-proof*).

- **Metric:** % tasks solved correctly, % solutions formally verified (when *gaia-proof* module is active)
- **Progression:** Track scores across self-training generations to measure model evolution

---

# ═══ EXTENSION MODULES ═══

Each module is an independent project that plugs into the GAIA Kernel. Modules have **no dependencies on each other** — only on the kernel. They can be developed in any order based on interest and resources.

---

## Module: `gaia-accel` — MLIR/IREE Tensor Acceleration

*Compile S-expression tensor operations to native hardware targets for edge deployment.*

**Kernel dependency:** K3 ($gscm$ DSL provides the compilation source language)

- [ ] **Selective MLIR/IREE Compilation** — Define macros for math/tensor operations. Macro parses S-expression, generates MLIR, and compiles it via IREE toolchain to native hardware targets via Guile FFI (critical for Tiny Recursive Models (TRM) integration).

---

## Module: `gaia-io` — Multimodal I/O

*Voice and vision channels for the GAIA kernel.*

**Kernel dependency:** K1 (Client-Server protocol)

- [ ] **Asynchronous Server on Guile Fibers** — Migrate server socket loops to cooperative Fibers, retaining POSIX threads for isolated `eval` execution to safely abort infinite loops. Switch to character-by-character streaming from LiteLLM.
- [ ] **Voice In (Speech-to-Text)** — Integrate `whisper.cpp` with VAD (Voice Activity Detection). Create an audio-listening worker in the Rust client that streams transcribed text to the Guile server.
- [ ] **Voice Out (Text-to-Speech)** — Integrate a lightweight local TTS engine (e.g., `Piper` or `Kokoro`) fed sentence-by-sentence to achieve near-zero latency.
- [ ] **Wayland "Screen Read" via PipeWire** — Background worker in the Rust client that captures the screen or specific app windows using XDG Desktop Portals and PipeWire, sending frames to a Vision-Language Model (VLM).
- [ ] **Multimodal Context Routing** — Update `llm-client.scm` to handle base64 image payloads and route them to vision-capable models (e.g. LLaVA, Pixtral).

---

## Module: `gaia-desktop` — Desktop Integration

*Native UI frontends for desktop environments.*

**Kernel dependency:** K1 (Client-Server protocol, S-expression socket API)

- [ ] **COSMIC Ecosystem Applet** — Develop a native, highly performant `libcosmic` Applet in Rust. Leverage `tokio` and the Iced architecture for zero-overhead, asynchronous UI rendering of streaming LLM responses.
- [ ] **GNOME/Ubuntu Integration** — Build a GNOME Shell Extension (GJS) for Ubuntu 26.04+ utilizing global overlays and shortcuts.
- [ ] **Doom Emacs / Crafted Emacs Module (`+gaia`)** — Write a native `gaia.el` Emacs package connecting to `/tmp/gaia.sock`, supporting interactive HITL diff prompts in buffers, and an Org-Babel interface.
- [ ] **GAIA-Edit IDE** — Standalone, modal text-editor written from scratch in Guile Scheme or Rust+Guile TUI.

---

## Module: `gaia-os` — System Integration & Transactional Self-Healing

*Expanding agentic system orchestration with GNU Guix safety guarantees.*

**Kernel dependency:** K2 (Goblins transactional vats for rollback)

- [ ] **Shepherd Service Integration** — Allow the agent to query and control system services via Shepherd API.
- [ ] **Transactional OS Self-Healing** — Use Goblins vat state and GNU Guix containers to run experimental configuration patches, with automatic atomic rollback via GNU Guix if system services crash.
- [ ] **Intent-Driven Wayland Compositor** — Utilize the `smithay` library (Rust) to build a custom window manager where the RLM engine arranges workspaces dynamically based on user intent.
- [ ] **Guix System OS Integration & Ad-hoc Science** — Execute AI-generated code in true `guix shell --container` ephemeral environments. Dynamically generate Guix manifests to spin up bit-reproducible sandboxes with specific scientific libraries on-the-fly. | *→ gaia-sci: Literate Research Export*

---

## Module: `gaia-proof` — Formal Verification & Theorem Proving

*Bridges to formal proof assistants for mathematical rigor.*

**Kernel dependency:** K2 (AND/OR Tree, AtomSpace), K3 ($gscm$ DSL, J-space Type Verification)

- [ ] **Formal Verification Bridges** — Generate SMT-LIB/Z3 specs and integrate Lean 4 to prove correctness of generated code and hypotheses.
- [ ] **J-space Guided Theorem Proving** — Connect Lean 4 proof-search failures back to the LLM via J-space intervention. When the symbolic prover gets stuck, project active proof goals or candidate axioms as J-lens steering vectors to bias LLM intuition towards viable search paths.
- [ ] **Global Goal Caching** — Build a shared subgoal database that hashes formal context and target states (`goal_id`) to share solved sub-problems instantly across nested sub-agents and save execution compute.
- [ ] **Cycle-Consistency & Triviality Filters** — Harden the auto-formalization pipeline by incorporating cycle-consistency verification (deformalization matches natural language intent) and testing against single-tactic solvers or fast counterexamples.

---

## Module: `gaia-sci` — Decentralized Scientist

*Large-scale knowledge ingestion, distributed reasoning, and reproducible research export.*

**Kernel dependency:** K2 (AtomSpace, G-Expressions), K3 (Self-Training Loop for curriculum learning)

- [ ] **Semantic Perception & Literature Ingestion (RAG)** — Vector/RAG databases to allow the LLM to sift through unstructured PDFs (e.g. arXiv, PubMed) to extract scientific abstracts, correlations, and factual claims.
- [ ] **MeTTa FFI to OpenCog Hyperon** — Export complex semantic subgraphs to Distributed AtomSpace (DAS) for high-performance logical reasoning.
- [ ] **Cognitive State Serialization** — Instead of serializing raw textual history to recursive sub-agents (RLM), serialize the current J-space activation coordinate vector (representing active working memory state) utilizing Guix G-expressions.
- [ ] **Literate Research Export (Data Provenance)** — Implement automated cryptographic hashing of all hypergraph derivations. Compile successful agent trajectories, proven logical paths, and Guix execution manifests into reproducible Org-mode or LaTeX research reports.

---

## Continuous integration — cross-cutting operations

This workstream is independent of the product and research timeline above. Its
purpose is to keep deterministic validation affordable and fast without making
CI tooling part of GAIA's runtime dependency manifest.

- [x] **Split CI by implementation stack** — Run Guile/GCAS, Rust CLI, and Emacs
  client validation in separate images. Keep `guix.scm` focused on the Scheme
  runtime and its tests; use a pinned Emacs CI image and the official Rust image
  for their respective adapters.
- [x] **Control routine compute usage** — Keep jobs interruptible, run stack jobs
  only for relevant path changes, cache Cargo downloads and build outputs, and
  reserve full coverage for `main`. GitLab.com Free currently includes 400
  hosted-runner compute minutes per namespace per month; reaching the quota
  blocks new hosted-runner jobs until quota renewal or purchase.
- [ ] **Versioned `gaia-scheme-ci` image** — Build and publish a pinned image with
  Guile, Goblins, Fibers, Wisp, certificates, and coverage tooling already
  prepared. Rebuild it only when its Guix channel lock, manifest, or image recipe
  changes. Measure cold and warm pipeline duration before making it the default.
- [ ] **Runner cost decision** — Compare GitLab hosted-runner usage with a small
  self-managed runner that retains `/gnu/store` and build caches. Jobs on a
  project-owned runner do not consume the GitLab.com hosted compute-minute
  quota, but runner maintenance, isolation of untrusted contributions, updates,
  and availability become project responsibilities.
- [ ] **CI portability fallback** — Keep validation behind Make targets so the
  same gates can move to GitHub Actions if GitLab pricing, the project plan, or
  runner availability changes. GitLab remains the canonical repository and
  GitHub remains a mirror unless that policy is changed explicitly.
- [ ] **Periodic cost review** — Track monthly minutes and per-job duration,
  revisit path rules after major protocol changes, and decide whether to buy
  additional minutes, apply for an eligible GitLab community program, operate a
  runner, or move execution to GitHub Actions.

Current limits and runner accounting should be rechecked before implementation:
[GitLab pricing](https://about.gitlab.com/pricing/),
[compute-minute guidance](https://about.gitlab.com/pricing/faq-compute-minutes/),
and [hosted-runner caching](https://docs.gitlab.com/ci/runners/hosted_runners/).

---

## References and other ideas worth adopting

- RLM Paper: https://arxiv.org/abs/2512.24601
- RelayLLM: https://arxiv.org/pdf/2601.05167
- FusionRoute: https://arxiv.org/pdf/2601.05106
- TRM: https://arxiv.org/abs/2510.04871 ([source](https://github.com/SamsungSAILMontreal/TinyRecursiveModels))
- J-space Paper (Verbalizable Representations Form a Global Workspace in Language Models): https://transformer-circuits.pub/2026/workspace/index.html
- AlphaProof Paper (Olympiad-level formal mathematical reasoning with reinforcement learning): https://www.nature.com/articles/s41586-025-09833-y
- AlphaProof Nexus Paper (Advancing Mathematics Research with AI-Driven Formal Proof Search): https://arxiv.org/abs/2605.22763
