# GAIA Roadmap

> *Last updated: 2026-08-14*
>
> This document tracks the development plan for the GAIA (GNU AI Assistant) project.
> For an introduction to the project, see [README.md](README.md).

---

## Current State Summary

GAIA has a functional legacy RLM-style investigation loop, persistent Guile REPL environment, safety validation,
trajectory logging, and LiteLLM integration. It also has a substantial GCAS substrate: Cognitive Objects, durable
state and events, a bounded Workspace implementation, Control primitives, structured memory, and auditable
Action/Result execution. The production `solve` path is still a centrally orchestrated single-pass pipeline, so
GAIA does not yet claim GCAS-Core conformance.

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

## GCAS-Core — Immediate Priority

- [x] **Cognitive Object Model** — Validated COs carry provenance, epistemic and verification statuses, temporal validity, confidence, and relations.
- [x] **Session Cognitive State** — Each server session owns durable CO state and an event log. Action outcomes receive linked reproducibility observations.
- [/] **Bounded Global Workspace** — Capacity, proposal metadata, scoring, admission, and broadcast exist. Production `solve` immediately advances one submitted CO at a time, so meaningful multi-candidate competition remains.
- [/] **Cognitive Control** — Transition, progress, stall, failure, and interruption monitoring exist. Budgets must move from the long-lived session to an explicit per-Goal cognitive process, with terminal state preventing late callbacks.
- [/] **Production processor assembly** — Processor and bus subscription contracts exist, but production `solve` invokes the LLM, executor, and deliberation directly. Planner and metacognition are currently labels rather than attached processors.
- [x] **Execution boundary** — Default `solve` and direct REPL cross explicit Action → Result/Failure boundaries with auditable links and reproduction observations. Richer capability policy remains post-Core hardening.
- [/] **Memory and context reconstruction** — Durable structured memory and transcript-free context reconstruction exist. Evidence/Claim consolidation, typed memory roles, and useful cross-turn retrieval remain.
- [/] **Recurrent cognitive cycle** — The deterministic showcase exercises the target event vocabulary, but production `solve` is linear and cannot replan after Result, Failure, Conflict, or Reflection.
- [ ] **Goal-specific verification and Answer Processor** — Define completion criteria per Goal; produce user-visible answers only from accepted Claims and terminal goal state.
- [ ] **Operational vertical acceptance test** — A failure-first Fibonacci scenario must reject an initial bad Action, feed evidence back through the bus, select a revised proposal, verify deterministic criteria, and terminate with `GoalCompleted`.

The detailed gap analysis and conformance gate are maintained in [docs/gcas-core-conformance.md](docs/gcas-core-conformance.md).

### Operational completion sequence

1. **Cognitive Process lifecycle** — Introduce a process object containing Goal,
   completion criteria, per-process budgets, progress state, and one terminal outcome.
2. **Event-driven processor assembly** — Attach Planner, Memory Retrieval,
   Generative, Execution, Deliberative, and Answer processors to the session Bus.
   Reduce the session orchestrator to lifecycle and client transport duties.
3. **Workspace scheduling rounds** — Collect proposals before admission, perform
   real competition, broadcast the winner, and release or supersede processed COs.
4. **Planning and feedback recurrence** — Represent Plan/Subgoal COs and route
   Result, Failure, Conflict, and Reflection back into planning or generation.
5. **Goal verification** — Add deterministic verifier contracts and ensure that
   execution success alone never satisfies a Goal.
6. **Answer policy and client observability** — Stop presenting raw LLM output as
   the system answer; expose current process, Goal, Workspace, COs, and terminal rationale.
7. **Memory consolidation** — Store verified evidence and claims, preserve
   conflicts and supersession, and retrieve structured facts across turns.
8. **Conformance acceptance** — Pass the failure-first vertical test plus restart,
   budget, interruption, and both-client protocol tests before claiming GCAS-Core.

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
- [/] **Chat History (Conversation Continuity)** — Session transcripts persist and `/clear` is supported. Transitional `solve` deliberately sends empty chat history, failed actions are not consistently saved to the transcript, and structured memory does not yet recover equivalent conversational facts.
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

- [/] **Atoms as Goblins Actors** — Leverage the `guile-goblins` library to create a lightweight, local AtomSpace *specifically for cognitive working memory (active relevance context, up to ~1000 nodes)*. Each semantic node and relation becomes an autonomous actor, leveraging Goblins' transactional vats (for automatic state rollback on execution errors) and asynchronous message passing (for spreading activation). *(Partially completed: Goblins is used for session REPLs, but not semantic mapping).* | *→ gaia-sci: Hyperon FFI, gaia-proof: Goal Caching*
- [ ] **STI/LTI Memory** — Implement Short-Term Importance (STI) and Long-Term Importance (LTI) weights for memory candidates. Decimate STI asynchronously after cognitive process transitions. | *→ gaia-sci: Cognitive State Serialization*
- [ ] **J-space to AtomSpace Mapping** — Integrate Jacobian Lens (J-lens) token projection weights directly with the Goblins-based AtomSpace. Use dynamic activation of J-space vectors during model forward passes to automatically adjust STI values of symbolic nodes in active memory. | *→ gaia-proof: J-space Guided Theorem Proving*
- [ ] **J-lens Activation Injection** — Use the J-lens intervention protocol (steering/patching) to inject symbolic states and REPL errors directly into the LLM's continuous workspace layers, bypassing context window clutter and directing model focus natively. | *→ K3: CRT, gaia-proof: J-space Guided Theorem Proving*
- [/] **Context Reconstruction** — Transitional `solve` builds a prompt from the current goal, admitted Workspace COs, lexically selected structured memories, and active constraints without appending the transcript. Production integration, richer retrieval, and evidence/claim consolidation remain.
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

## References and other ideas worth adopting

- RLM Paper: https://arxiv.org/abs/2512.24601
- RelayLLM: https://arxiv.org/pdf/2601.05167
- FusionRoute: https://arxiv.org/pdf/2601.05106
- TRM: https://arxiv.org/abs/2510.04871 ([source](https://github.com/SamsungSAILMontreal/TinyRecursiveModels))
- J-space Paper (Verbalizable Representations Form a Global Workspace in Language Models): https://transformer-circuits.pub/2026/workspace/index.html
- AlphaProof Paper (Olympiad-level formal mathematical reasoning with reinforcement learning): https://www.nature.com/articles/s41586-025-09833-y
- AlphaProof Nexus Paper (Advancing Mathematics Research with AI-Driven Formal Proof Search): https://arxiv.org/abs/2605.22763
