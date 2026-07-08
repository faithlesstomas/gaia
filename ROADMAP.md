# GAIA Roadmap

> *Last updated: 2026-07-03*
>
> This document tracks the development plan for the GAIA (GNU AI Assistant) project.
> For an introduction to the project, see [README.md](README.md).

---

## Current State Summary

GAIA is a functional AI assistant with a working RLM (Recursive Language Model) loop, 
persistent Guile REPL environment, safety validation, trajectory logging, and LiteLLM integration.
The core agentic loop is stable and has been validated with Gemma 4 and other models.

**Architecture:** Rust Client - GAIA Server (Guile REPL) - LiteLLM Proxy - LLM backends (Ollama, Lemonade, external LLM API etc.)

---

## Phase 0 — Foundation ✅ (Completed)

Core infrastructure that is already built and working.

- [x] **RLM Loop** — Multi-step agentic loop with code extraction, execution, and feedback
- [x] **Persistent REPL Environment** — Variables and functions survive across RLM steps within a task
- [x] **Static Safety Validator** — AST-level recursive scan for banned primitives (`system*`, `delete-file`, etc.)
- [x] **Module-based Sandbox** — Whitelisted imports for AI-generated code
- [x] **FINAL/CONFIDENCE Signals** — Structured completion and confidence extraction
- [x] **Structured Error Handling** — Syntax, permission, and runtime error classification with feedback
- [x] **LiteLLM Integration** — OpenAI-compatible API client replacing the legacy RAI server
- [x] **Trajectory Logging & Curation** — Every interaction logged to timestamped `.jsonl` files, split into success/failure datasets via `curator.scm`
- [x] **Thinking Mode** — Native `<|think|>` tag support for Gemma 4 reasoning
- [x] **Live Monitor** — `make monitor` for real-time trajectory viewing
- [x] **Benchmark Suite** — Needle-in-a-Haystack (NIAH) benchmark for RLM validation
- [x] **System Tools** — File ops, grep, sed, awk, journalctl wrappers with flexible arguments in `tools.scm`
- [x] **Parenthesis Analyzer & Auto-healing** — Mismatched parens auto-repair and escape sequence healing in `sandbox.scm`
- [x] **Last-block Extraction** — Prefers last code block in LLM response
- [x] **Auto LiteLLM Server** — `make run` auto-starts LiteLLM if not running
- [x] **Chat History (Conversation Continuity)** — Sliding window of `(user, query) → (assistant, FINAL_answer)` context across sessions, with `/clear` support
- [x] **Native CLI Client (Rust)** — Build a fast, native terminal client using the "scrollback" REPL model with `rustyline`
- [x] **S-expression Protocol over UNIX Sockets** — S-expression communication socket layer parsed in Rust via `lexpr`
- [x] **Human-in-the-Loop (HITL) Sandbox** — Interactive permission system in the Rust client to intercept risky AST-detected operations

---

## Phase 1 — Parenthesis Hardening & CLI Refactoring (Immediate Priority)

Hardening the agentic loop to handle syntax constraints of smaller local models (e.g. 3B `gemma4:e2b`) and decoupling the client/server layout.

- [x] **Wisp (SRFI-119) Integration** — Implement the whitespace-to-Lisp parser in the execution pipeline. This allows LLMs to write Scheme code using Python-like indentation, solving the "parenthesis blindness" of small models while retaining Guile's AST-level safety and homoiconicity.
- [x] **Client-Server Refactoring (De-bloat gaia-cli)** — Fully delegate slash command routing to the server and remove local output parsing (e.g. `/help` text definitions, and alist formatting). Client should become a presentation-agnostic renderer of pre-parsed events.
- [x] **Advanced Terminal UX & Inline Status** — Non-blocking inline spinner or bottom status bar showing current background RLM execution state using ANSI cursor control codes or `indicatif`.
- [x] **Expanded Auto-healing** — Programmatic unmatched parens closing and syntax self-repair hardening before running `eval`.
- [x] **Modularize Actors Framework** — Split the monolithic `actors.scm` into separate files (`sandbox-actor.scm`, `agent-actor.scm`, `session-orchestrator.scm`) to separate session orchestration, environment evaluation, and agent cognitive logic.
- [/] **HITL Security Hardening (Command Injection)** — Replace simple prefix checks in `run-command` with shell-token parsing or direct executable invocation (`system*`) to prevent shell injection bypasses (e.g., `grep; rm -rf /`). *(Partially completed: basic safety checks checking for forbidden characters `#\; #\& #\| #\` #\$` are implemented, but shell-token parsing / direct system* execution is pending).*
- [x] **Efficient HITL Sync** — Replace busy-waiting `usleep` polling in `permission-sink` with Guile mutexes and condition variables.
- [x] **HITL Metadata Exchange** — Define an S-expression metadata format for permission requests so the client doesn't need to parse Scheme AST to print file diffs.
- [/] **HITL Permission Scoping** — Introduce session/directory scoping in client approvals to reduce prompt fatigue (e.g., "Allow all write-file commands in this path"). *(Partially completed: server-side matching scopes via directory/always rules are implemented, but client UI integration is pending).*
- [x] **Bailout Mechanism** — If confidence drops drastically or the error loop persists too long, pause the main loop and spawn a diagnostic sub-agent.
- [x] **High-level Standard Library for LLM** — Add ready-made higher-order procedures to `tools.scm` to offload the model from writing complex nested loops:
  - `(read-files '("A" "B"))` — batch file reading
  - `(patch-file path old-string new-string)` — in-place string replacement in files
  - `(map-files dir pattern proc)` — apply procedure to matching files
- [ ] **Code Instrumentation & Auto-Logging** — Automatically rewrite LLM-generated code to wrap function calls in error handlers.
- [ ] **Auto-Scaffolding** — On agent startup in a directory, silently run a lightweight `(list-files)` and inject the directory map into the system prompt for immediate spatial awareness.
- [ ] **Deterministic Replay** — Replay saved trajectory files offline without API costs for debugging and demonstration purposes.

---

## Phase 2 — Cognitive Working Memory (Local AtomSpace & STI/LTI)

*Moved from former Phase 7 to address context rot and context window clogging.*

- [/] **Atoms as Goblins Actors** — Leverage the `guile-goblins` library to create a lightweight, local AtomSpace *specifically for cognitive working memory (active relevance context, up to ~1000 nodes)*. Each semantic node and relation becomes an autonomous actor, leveraging Goblins' transactional vats (for automatic state rollback on execution errors) and asynchronous message passing (for spreading activation). *(Partially completed: Goblins is used for session REPLs, but not semantic mapping).*
- [ ] **STI/LTI Memory Loop** — Implement Short-Term Importance (STI) and Long-Term Importance (LTI) weights for atoms. Decimate STI asynchronously (decay by $X\%$) after each RLM step.
- [ ] **J-space to AtomSpace Mapping** — Integrate Jacobian Lens (J-lens) token projection weights directly with the Goblins-based AtomSpace. Use dynamic activation of J-space vectors during model forward passes to automatically adjust STI values of symbolic nodes in active memory.
- [ ] **J-lens Activation Injection** — Use the J-lens intervention protocol (steering/patching) to inject symbolic states and REPL errors directly into the LLM's continuous workspace layers, bypassing context window clutter and directing model focus natively.
- [ ] **Context-Based Prompt Hydration** — Rebuild the server's prompt generator to only feed: *Constant system prompt* + *Top-N atoms with highest STI (active memory)* + *Last RLM step result*. Old RLM step text logs are pruned, resolving context rot.
- [ ] **G-Expressions ("Context Teleportation")** — Use GNU Guix's G-expressions (`#~`) to serialize variable contexts and modules when spawning sub-agents.
- [ ] **The Self-Modifying Agent** — Allow GAIA to refactor its own `rlm-loop` at runtime by treating the loop logic as a mutable S-expression.

---

## Phase 3 — GAIA Scheme DSL ($gscm$) & Tensor Acceleration

*Moved from former Phase 6 to lay down safe language bounds and optimization before OS integration.*

- [ ] **Embedded DSL via Guile Macros** — Custom syntax macros using `syntax-case` to define a safe sub-language ($gscm$) that automatically enforces type ontologies and physical dimension units.
- [ ] **J-space Type Constraint Verification** — Use the J-lens to verify if internal continuous representations in the model's global workspace align with the symbolic type constraints of the `$gscm` DSL *prior* to token generation. Halt generation or apply J-space patching if dimensional or ontological mismatches (e.g. meter vs. second) are detected in flight.
- [ ] **Selective MLIR/IREE Compilation** — Define macros for math/tensor operations. Macro parses S-expression, generates MLIR, and compiles it via IREE toolchain to native hardware targets via Guile FFI (critical for Tiny Recursive Models (TRM) integration).

---

## Phase 4 — Closing the Self-Improvement Loop (`make learn`)

*Moved from former Phase 3 to build on top of Wisp data and AtomSpace logs.*

- [ ] **DPO/ORPO Dataset Curation** — Refactor `curator.scm`. If code generated by LLM causes syntax errors but gets repaired via auto-healing or subsequent steps, output a comparison pair: `[Broken Code = Rejected]` and `[Healed/Fixed Code = Chosen]`.
- [ ] **Counterfactual Reflection Training (CRT)** — Implement a training pipeline using J-space alignment. Train the model to generate self-reflection tokens if interrupted mid-task, shaping the J-space internally with safety and alignment concepts (e.g. `integrity`, `honest`, `failure`), and improving task robustness during autonomous evaluations.
- [ ] **Trajectory Cleaning (Compact Logging)** — Modify `curator.scm` to strip dead-end attempts before writing to `.jsonl`. Address the auto-healing issue by rewriting history for Ideal SFT.
- [ ] **AST-based Training (Code-as-Data)** — Instead of logging textual code corrections, log the evolution of AST structure to show how the model improved logic step-by-step.
- [ ] **External GPU Training Node** — Script `make learn` to upload dataset to external node using QLoRA/Unsloth (e.g. for adapter fine-tuning).
- [ ] **Champion/Challenger System** — After training a new adapter: run benchmark -> compare with current model -> promote if better.
- [ ] **Automatic Hot-Swap** — Detect newly trained adapter and hot-reload LiteLLM configuration without interrupting current sessions.

---

## Phase 5 — System Integration & Multimodal I/O

Bridging GAIA to desktop environments and voice channels.

- [ ] **Asynchronous Server on Guile Fibers** — Migrate server socket loops to cooperative Fibers, retaining POSIX threads for isolated `eval` execution to safely abort infinite loops. Switch to character-by-character streaming from LiteLLM.
- [ ] **Voice In (Speech-to-Text)** — Integrate `whisper.cpp` with VAD (Voice Activity Detection). Create an audio-listening worker in the Rust client that streams transcribed text to the Guile server.
- [ ] **Voice Out (Text-to-Speech)** — Integrate a lightweight local TTS engine (e.g., `Piper` or `Kokoro`) fed sentence-by-sentence to achieve near-zero latency.
- [ ] **Wayland "Screen Read" via PipeWire** — Background worker in the Rust client that captures the screen or specific app windows using XDG Desktop Portals and PipeWire, sending frames to a Vision-Language Model (VLM).
- [ ] **Multimodal Context Routing** — Update `llm-client.scm` to handle base64 image payloads and route them to vision-capable models (e.g. LLaVA, Pixtral).
- [ ] **COSMIC Ecosystem Applet** — Develop a native, highly performant `libcosmic` Applet in Rust. Leverage `tokio` and the Iced architecture for zero-overhead, asynchronous UI rendering of streaming LLM responses.
- [ ] **GNOME/Ubuntu Integration** — Build a GNOME Shell Extension (GJS) for Ubuntu 26.04+ utilizing global overlays and shortcuts.
- [ ] **Doom Emacs / Crafted Emacs Module (`+gaia`)** — Write a native `gaia.el` Emacs package connecting to `/tmp/gaia.sock`, supporting interactive HITL diff prompts in buffers, and an Org-Babel interface.
- [ ] **GAIA-Edit IDE** — Standalone, modal text-editor written from scratch in Guile Scheme or Rust+Guile TUI.

---

## Phase 6 — GAIA OS & Transactional Self-Healing

Expanding agentic system orchestration and safety loops.

- [ ] **Shepherd Service Integration** — Allow the agent to query and control system services via Shepherd API.
- [ ] **Transactional OS Self-Healing** — Use Goblins vat state and GNU Guix containers to run experimental configuration patches, with automatic atomic rollback via GNU Guix if system services crash.
- [ ] **Intent-Driven Wayland Compositor** — Utilize the `smithay` library (Rust) to build a custom window manager where the RLM engine arranges workspaces dynamically based on user intent.
- [ ] **Guix System OS Integration & Ad-hoc Science** — Execute AI-generated code in true `guix shell --container` ephemeral environments. Dynamically generate Guix manifests to spin up bit-reproducible sandboxes with specific scientific libraries on-the-fly.

---

## Phase 7 — Decentralized Scientist & Lean 4 Bridges

Formal verification and large-scale semantic graphs.

- [ ] **Semantic Perception & Literature Ingestion (RAG)** — Vector/RAG databases to allow the LLM to sift through unstructured PDFs (e.g. arXiv, PubMed) to extract scientific abstracts, correlations, and factual claims.
- [ ] **Most FFI to OpenCog Hyperon** — Export complex semantic subgraphs to Distributed AtomSpace (DAS) for high-performance logical reasoning.
- [ ] **Formal Verification Bridges** — Generate SMT-LIB/Z3 specs and integrate Lean 4 to prove correctness of generated code and hypotheses.
- [ ] **J-space Guided Theorem Proving** — Connect Lean 4 proof-search failures back to the LLM via J-space intervention. When the symbolic prover gets stuck, project active proof goals or candidate axioms as J-lens steering vectors to bias LLM intuition towards viable search paths.
- [ ] **Cognitive State Serialization** — Instead of serializing raw textual history to recursive sub-agents (RLM), serialize the current J-space activation coordinate vector (representing active working memory state) utilizing Guix G-expressions.
- [ ] **Literate Research Export (Data Provenance)** — Implement automated cryptographic hashing of all hypergraph derivations. Compile successful agent trajectories, proven logical paths, and Guix execution manifests into reproducible Org-mode or LaTeX research reports.

---

## References and other ideas worth adopting

- RLM Paper: https://arxiv.org/abs/2512.24601
- RelayLLM: https://arxiv.org/pdf/2601.05167
- FusionRoute: https://arxiv.org/pdf/2601.05106
- TRM: https://arxiv.org/abs/2510.04871 ([source](https://github.com/SamsungSAILMontreal/TinyRecursiveModels))
- J-space Paper (Verbalizable Representations Form a Global Workspace in Language Models): https://transformer-circuits.pub/2026/workspace/index.html
