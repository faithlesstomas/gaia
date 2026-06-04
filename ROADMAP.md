# GAIA Roadmap

> *Last updated: 2026-05-12*
>
> This document tracks the development plan for the GAIA (GNU AI Assistant) project.
> For an introduction to the project, see [README.md](README.md).

---

## Current State Summary

GAIA is a functional AI assistant with a working RLM (Recursive Language Model) loop, 
persistent Guile REPL environment, safety validation, trajectory logging, and LiteLLM integration.
The core agentic loop is stable and has been validated with Gemma 4 and other models.

**Codebase:** ~2350 lines of GNU Guile Scheme + Native Rust CLI Client + 12 test scripts
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
- [x] **CLI with Slash Commands** — `/ask`, `/eval`, `/model`, `/thinking`, `/train`, `/help`, `/exit`
- [x] **Trajectory Logging** — Every interaction logged to timestamped `.jsonl` files
- [x] **Dataset Curation** — `curator.scm` splits trajectories into success/failure datasets
- [x] **Thinking Mode** — Native `<|think|>` tag support for Gemma 4 reasoning
- [x] **Live Monitor** — `make monitor` for real-time trajectory viewing
- [x] **Benchmark Suite** — Needle-in-a-Haystack (NIAH) benchmark for RLM validation
- [x] **System Tools** — File ops, grep, sed, awk, journalctl wrappers with flexible arguments
- [x] **Guile Documentation Lookup** — `search-guile-manual` tool for model self-help
- [x] **Parenthesis Analyzer** — Syntax error hints for mismatched parens
- [x] **Last-block Extraction** — Prefers last code block in LLM response (self-correction support)
- [x] **Auto LiteLLM Server** — `make run` auto-starts LiteLLM if not running
- [x] **Chat History (Conversation Continuity)** — Maintained a sliding window of `(user, query) → (assistant, FINAL_answer)`
  pairs across CLI interactions. New queries receive context from previous exchanges. Added `/clear` command.

---

## Phase 1 — RLM Core Improvements & Homoiconicity

Hardening the agentic loop to handle the "parenthesis blindness" of smaller language models and leveraging Lisp's code-as-data nature.

- [ ] **Wisp (SRFI-119) Integration** — Implement the Whitespace-to-Lisp parser in the execution pipeline.
  This allows LLMs to write Scheme code using Python-like indentation, effectively solving the "parenthesis blindness"
  of small models while retaining Guile's AST-level safety and homoiconicity.
- [x] **Polyglot Tooling (`run-python`)** — Add a `(run-python "code")` tool to `tools.scm` backed by a persistent `python-sandbox-actor` running in a secure Guix container, enabling a stateful multi-language REPL.
- [ ] **RelayLLM with external API** - In phase 5, we will train own models for RelayLLM,
  but at this moment we can first use external LLM providers API for token Collaboration with local LLM.
- [x] **Context Pruning (Step Compaction)** — Tackle the context rot problem by summarizing older RLM steps in the textual prompt while preserving 100% of defined REPL state in Goblins memory.
- [ ] **Bailout Mechanism** — If confidence drops drastically or the error loop persists too long, pause the main loop and spawn a diagnostic sub-agent.
- [x] **Auto-healing (Syntax Self-Repair)** — Instead of rejecting code with missing parentheses, programmatically close unmatched `)` before calling `eval`.
- [ ] **High-level Standard Library for LLM** — Add ready-made higher-order procedures to `tools.scm`
  to offload the model from writing complex nested loops:
  - `(read-files '("A" "B"))` — batch file reading
  - `(patch-file path old-string new-string)` — in-place string replacement in files
  - `(map-files dir pattern proc)` — apply procedure to matching files
- [ ] **Code Instrumentation & Auto-Logging** — Automatically rewrite LLM-generated code to wrap function calls in error handlers.
- [ ] **G-Expressions ("Context Teleportation")** — Use GNU Guix's G-expressions (`#~`) to serialize variable contexts and modules when spawning sub-agents.
- [ ] **The Self-Modifying Agent** — Allow GAIA to refactor its own `rlm-loop` at runtime by treating the loop logic as a mutable S-expression.
- [ ] **Capability-Based Security (Spritely Goblins):** Transition from the current static AST whitelisting to a granular,
  object-capability model (Ocap) for the RLM environment using the **Spritely Goblins** framework. This introduces a secure Actor Model, transactional REPL rollbacks (rollback vat state on error), active Human-in-the-Loop (HITL) capability authorization, and Vat Forking for parallel strategy exploration.
- [ ] **Semantic Texinfo Navigation:** Upgrade `search-guile-manual` to use semantic/vector indexing across all GNU Info manuals.

---

## Phase 2 — Headless Architecture & Terminal UX

Transition from monolith to a modern client-server architecture inspired by tools like Claude Code / Cline.

- [ ] **Headless GAIA Engine (Fibers-based Refactoring)** — Migrate the server orchestration to **Guile Fibers**
  for high-performance, non-blocking I/O. Implement cooperative cancellation for LLM network requests (e.g., closing the port).
  **Crucially:** Maintain POSIX Threads for isolated `rlm-execute` calls so that AI-generated infinite loops can still be
  aborted preemptively using `cancel-thread` without hanging the Fibers scheduler.
- [ ] **Response Streaming** — Switch to character-by-character streaming from LiteLLM.
  Stream thoughts (`<|think|>`) and response tokens in real-time to the Rust client.
- [x] **Native CLI Client (Rust)** — Build a fast, native terminal client using the "scrollback" REPL model with `rustyline`
  for rich input (history, auto-complete), `pulldown_cmark` for Markdown rendering, and asynchronous status updates, replacing the older TUI concepts.
- [x] **S-expression Protocol over UNIX Sockets** — Define a lightweight communication protocol based on Scheme S-expressions
  to support `eval` requests, `event` streams (tokens, thoughts), and `interrupt` signals, natively parsing them in Rust via `lexpr`.
- [x] **Human-in-the-Loop (HITL) Sandbox** — Implement an interactive permission system
  in the Rust client to intercept risky AST-detected operations (e.g., `delete-file`).
- [ ] **Auto-Scaffolding** — On agent startup in a directory, silently run a lightweight `(list-files)`
  and inject the directory map into the system prompt for immediate spatial awareness.
- [ ] **Deterministic Replay** — Replay saved trajectory files offline without API costs for debugging and demonstration purposes.

---

## Phase 3 — Continuous Learning (Fine-Tuning & Data)

Closing the self-improvement loop where GAIA learns from its own mistakes, as outlined in `training_spec.md` and `fine_tuning_guide.md`.

- [ ] **Trajectory Cleaning (Compact Logging)** — Modify `curator.scm` to strip dead-end attempts before writing to `.jsonl`.
  Address the auto-healing issue by rewriting history for Ideal SFT or emitting pairs for DPO/ORPO training (Broken code = Rejected, Healed code = Chosen).
- [ ] **AST-based Training (Code-as-Data)** — Instead of logging textual code corrections, log the evolution of AST structure to show how the model improved logic step by step.
- [ ] **Training Script (`make learn`)** — Implement the Python training script (Unsloth/QLoRA) and wire it into the Makefile.
- [ ] **Champion/Challenger System** — After training a new adapter: run benchmark → compare with current model → promote if better.
- [ ] **Hot-Swap Adapters** — Automatically reload LiteLLM config after training to serve the newly fine-tuned model without manual restart.

---

## Phase 4 — Multimodal I/O (Vision & Voice)

Transforming GAIA from a text-only interface to a fully conversational and visually aware assistant,
using highly optimized local models to preserve hardware resources (APU/CPU).

- [ ] **Voice In (Speech-to-Text):** Integrate `whisper.cpp` with VAD (Voice Activity Detection).
  Create an audio-listening worker in the Rust client that streams transcribed text directly to the Guile Headless Server over JSON-RPC.
- [ ] **Voice Out (Text-to-Speech):** Integrate a lightweight local TTS engine (e.g., `Piper` or `Kokoro`).
  Leverage the Headless Server's character streaming to feed the TTS engine sentence-by-sentence, achieving near-zero latency conversational responses.
- [ ] **Wayland "Screen Read" via PipeWire (Desktop Phase):** Implement a background worker in the Rust client that captures the screen
  or specific app windows using XDG Desktop Portals and PipeWire, sending frames to a Vision-Language Model (VLM) via LiteLLM.
- [ ] **Multimodal Context Routing:** Update `llm-client.scm` to handle base64 image payloads and route them to vision-capable
  models (e.g., LLaVA, Pixtral, or multimodal Gemma variants) when the user asks "What am I looking at?".
- [ ] **Compositor "God View" (OS Phase Prep):** Architect the system so that when transitioning to the custom Smithay Wayland Compositor, GAIA
  bypasses PipeWire and directly reads the zero-copy GPU buffers of active windows for instant visual context.

---


## Phase 5 — Desktop Integration (The Two-Pronged Strategy)

Evolving GAIA from a terminal utility into a deeply integrated OS assistant, utilizing the Headless Engine and JSON-RPC protocol to serve multiple front-ends.

- [ ] **Phase 4A: GNOME/Ubuntu Integration (Market Adoption):** Build a GNOME Shell Extension (GJS) for Ubuntu 26.04+.
  Implement a global overlay activated by shortcuts for quick intent processing, and utilize XDG Desktop Portals for secure screen context and notification reading.
- [ ] **Phase 4B: COSMIC Ecosystem (The Future Foundation):** Develop a native, highly performant `libcosmic` Applet in Rust.
  Leverage `tokio` and the Iced architecture for zero-overhead, asynchronous UI rendering of streaming LLM responses.
- [ ] **Alternative Interfaces (Optional):** Explore browser-based monitoring (Guile Hoot / WASM) or a dedicated Rust-based IDE (Tauri/Iced)
  tightly coupled with the Guile REPL.

---

## Phase 6 — GAIA OS & System Orchestration

Transforming GAIA into a standalone, AI-first operating environment and exploring cutting-edge inference architectures.

- [ ] **Intent-Driven Wayland Compositor:** Utilize the `smithay` library (Rust) to build a custom window manager
  where the RLM engine arranges workspaces dynamically based on user intent.
- [ ] **Transactional OS Self-Healing:** Leverage GNU Guix's rollback capabilities alongside Shepherd Service Orchestration.
  Allow the agent to monitor crashing system services via Shepherd API, safely experiment with configuration patches,
  and automatically rollback if the system becomes unstable.
- [ ] **Guix System OS Integration & Ad-hoc Science:** Execute AI-generated code in true `guix shell --container` ephemeral environments.
  Dynamically generate Guix manifests to spin up bit-reproducible sandboxes with specific scientific libraries on-the-fly.
- [ ] **Tiny Recursive Model (TRM) & MLIR/IREE:** Explore recursive architectures (arxiv:2510.04871) for drastically reduced VRAM.
  Compile trained models to optimized hardware-specific artifacts using MLIR/IREE to bypass PyTorch overhead.
- [ ] **RelayLLM & FusionRoute:** Implement token-level collaboration and multi-expert routing layers in the Headless Server.


## Phase 7 — Neuro-Symbolic AI & The Automated Scientist Workflow

Transforming GAIA into a rigorous mathematical and scientific researcher capable of formal hypothesis generation, reproducible experimentation, and theorem proving.
This phase integrates the complete synergistic pipeline: RAG (System 1 perception) + AtomSpace (System 2 reasoning) + Goblins (Orchestration) + Guix (Execution).

- [ ] **Semantic Perception & Literature Ingestion (RAG):** Implement Vector/RAG databases as the rapid external sensory memory.
  Allow the LLM to sift through millions of unstructured PDFs (e.g., arXiv, PubMed) to extract scientific abstracts, correlations,
  and factual claims before passing them to the logical evaluator.
- [ ] **Knowledge Representation & Logical Inference (OpenCog / AtomSpace):** Integrate AtomSpace as the core working memory and truth-maintenance engine.
  The LLM translates facts extracted via RAG into native Scheme S-expressions (Atoms). AtomSpace runs Probabilistic Logic Networks (PLN) on this hypergraph
  to evaluate logical consistency, find contradictions, and generate novel hypotheses without autoregressive hallucinations.
- [ ] **Distributed Agent Orchestration (Spritely Goblins):** Build the "Adversarial Peer-Review Protocol" natively using the Spritely Goblins Actor Model.
  Sub-agents (Challenger and Proposer) operate asynchronously with strict, capability-based access tokens to logically falsify or find edge-cases in proposed hypotheses.
- [ ] **Reproducible Sandbox Execution (GNU Guix):** Dynamically generate Guix manifests to spin up bit-reproducible `guix shell --container` environments.
  Allow the Goblins-orchestrated agents to empirically test AtomSpace conclusions by compiling and running ad-hoc simulations safely.
- [ ] **Scientific DSL & Dimensional Analysis:** Develop custom Guile macros tailored for researchers (e.g., physics, cosmology).
  Integrate physical unit systems directly into `(gaia tools)` to prevent dimensional errors in LLM-generated scientific code before it enters AtomSpace.
- [ ] **Formal Verification Bridges (SMT-LIB & Lean 4):** Equip the agent with tools to generate SMT-LIB/Z3 specifications from Scheme code and AtomSpace hypergraphs
  to mathematically prove algorithm correctness. Retain an integration path to Lean 4 for formal mathematical theorem proving.
- [ ] **Literate Research Export (Data Provenance):** Implement automated cryptographic hashing of all hypergraph derivations.
  Automatically compile successful agent trajectories, proven logical paths from AtomSpace, and Guix execution manifests into fully
  reproducible Org-mode or LaTeX research reports.


---

## References and other ideas worth adopting

- RLM Paper: https://arxiv.org/abs/2512.24601
- RelayLLM: https://arxiv.org/pdf/2601.05167
- FusionRoute: https://arxiv.org/pdf/2601.05106
- TRM: https://arxiv.org/abs/2510.04871 ([source](https://github.com/SamsungSAILMontreal/TinyRecursiveModels))
