# GAIA Roadmap

> *Last updated: 2026-05-01*
>
> This document tracks the development plan for the GAIA (GNU AI Assistant) project.
> For an introduction to the project, see [README.md](README.md).

---

## Current State Summary

GAIA is a functional AI assistant with a working RLM (Recursive Language Model) loop, persistent Guile REPL environment,
safety validation, trajectory logging, and LiteLLM integration.
The core agentic loop is stable and has been validated with Gemma 4 and other models.

**Codebase:** ~2350 lines of GNU Guile Scheme + 12 test scripts
**Architecture:** GAIA (Guile) ↔ LiteLLM Proxy ↔ LLM backends (Gemma, Ollama, Gemini, etc.)

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

Hardening the agentic loop to handle the "parenthesis blindness" of smaller models (Gemma 4, Ministral) and leveraging Lisp's code-as-data nature.

- [ ] **Wisp (SRFI-119) Integration** — Implement the Whitespace-to-Lisp parser in the execution pipeline.
  This allows LLMs to write Scheme code using Python-like indentation, effectively solving the "parenthesis blindness"
  of small models while retaining Guile's AST-level safety and homoiconicity.
- [ ] **Polyglot Tooling (`run-python`)** — Add a `(run-python "code")` tool to `tools.scm`.
  This allows the agent to orchestrate system logic safely in Guile, while delegating heavy data processing to Python scripts
  running inside isolated, ephemeral Guix containers.
- [ ] **RelayLLM with external API** - In phase 5, we will train own models for RelayLLM,
  but at this moment we can first use external LLM providers API for token Collaboration with local LLM.
- [ ] **Context Pruning** — If the model makes 3+ consecutive syntax/logic errors, prune failed attempts from the transcript
  and replace with a compact summary (e.g. `[System: Too many errors, history cleared. Write simpler code]`) to prevent "doom loops".
- [ ] **Bailout Mechanism** — If confidence drops drastically or the error loop persists too long, pause the main loop
  and spawn a diagnostic sub-agent to identify the logical problem.
- [x] **Auto-healing (Syntax Self-Repair)** — Instead of rejecting code with missing parentheses, programmatically close unmatched `)`
  before calling `eval`. Use the existing `analyze-parentheses` function to detect and fix simple cases.
- [ ] **High-level Standard Library for LLM** — Add ready-made higher-order procedures to `tools.scm`
  to offload the model from writing complex nested loops:
  - `(read-files '("A" "B"))` — batch file reading
  - `(patch-file path old-string new-string)` — in-place string replacement in files
  - `(map-files dir pattern proc)` — apply procedure to matching files
- [ ] **Code Instrumentation & Auto-Logging** — Automatically rewrite LLM-generated code to wrap function calls in error handlers
  or performance loggers using Scheme macros.
- [ ] **G-Expressions ("Context Teleportation")** — Use GNU Guix's G-expressions (`#~`) to serialize variable contexts and modules
  when spawning sub-agents, solving the data transfer problem in `delegate` blocks.
- [ ] **The Self-Modifying Agent** — Allow GAIA to refactor its own `rlm-loop` at runtime by treating the loop logic as a mutable S-expression.

---

## Phase 2 — Headless Architecture & Terminal UX

Transition from monolith to a modern client-server architecture inspired by tools like Claude Code / Cline.

- [ ] **Headless GAIA Engine (Fibers-based)** — Rebuild the engine as a background server using **Guile Fibers**
  for high-performance server orchestration and non-blocking I/O. Maintain POSIX Threads for isolated `rlm-execute`
  calls and communicate via local UNIX Sockets.
- [ ] **Response Streaming** — Switch to character-by-character streaming from LiteLLM.
  Stream thoughts (`<|think|>`) and response tokens in real-time to the Rust client.
- [ ] **Native CLI Client (Rust + `ratatui`)** — Build a fast, native terminal client with `rustyline` for rich input,
  `pulldown_cmark` for Markdown rendering, and asynchronous status updates.
- [ ] **JSON-RPC Protocol over UNIX Sockets** — Define a lightweight communication protocol
  to support `eval` requests, `event` streams (tokens, thoughts), and `interrupt` signals.
- [ ] **Human-in-the-Loop (HITL) Sandbox** — Implement an interactive permission system
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

## Phase 4 — Desktop Integration (The Two-Pronged Strategy)

Evolving GAIA from a terminal utility into a deeply integrated OS assistant, utilizing the Headless Engine and JSON-RPC protocol to serve multiple front-ends.

- [ ] **Phase 4A: GNOME/Ubuntu Integration (Market Adoption):** Build a GNOME Shell Extension (GJS) for Ubuntu 26.04+.
  Implement a global overlay activated by shortcuts for quick intent processing, and utilize XDG Desktop Portals for secure screen context and notification reading.
- [ ] **Phase 4B: COSMIC Ecosystem (The Future Foundation):** Develop a native, highly performant `libcosmic` Applet in Rust.
  Leverage `tokio` and the Iced architecture for zero-overhead, asynchronous UI rendering of streaming LLM responses.
- [ ] **Alternative Interfaces (Optional):** Explore browser-based monitoring (Guile Hoot / WASM) or a dedicated Rust-based IDE (Tauri/Iced)
  tightly coupled with the Guile REPL.

---

## Phase 5 — The Ultimate Vision (GAIA OS & Advanced Research)

Transforming GAIA into a standalone, AI-first operating environment and exploring cutting-edge inference architectures.

- [ ] **Intent-Driven Wayland Compositor:** Utilize the `smithay` library (Rust) to build a custom window manager where the RLM engine arranges workspaces dynamically based on user intent.
- [ ] **Guix System OS Integration:** Execute AI-generated code in true `guix shell --container` ephemeral environments for bit-reproducible isolation at the OS level.
- [ ] **Tiny Recursive Model (TRM):** Explore recursive architectures ([arxiv:2510.04871](https://arxiv.org/abs/2510.04871)) for drastically reduced VRAM requirements via looped layer matrices.
- [ ] **MLIR/IREE Compilation:** Compile trained models to optimized hardware-specific artifacts for inference without PyTorch overhead. See: MLIR, IREE, TVM.
- [ ] **RelayLLM (Token-Level Collaboration):** Train an SLM (Small Language Model) controller using GRPO to generate tokens and call a "Teacher" LLM only for difficult reasoning steps via a `<call>` command.
- [ ] **FusionRoute (Multi-Expert Routing):** Implement a routing layer in the Headless Server that selects the best specialized expert per token and adds a complementary logit to stabilize output.

---

## References

- RLM Paper: https://arxiv.org/abs/2512.24601
- RelayLLM: https://arxiv.org/pdf/2601.05167
- FusionRoute: https://arxiv.org/pdf/2601.05106
- TRM: https://arxiv.org/abs/2510.04871 ([source](https://github.com/SamsungSAILMontreal/TinyRecursiveModels))
