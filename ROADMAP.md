# GAIA Roadmap

> *Last updated: 2026-04-18*
>
> This document tracks the development plan for the GAIA (GNU AI Assistant) project.
> For an introduction to the project, see [README.md](README.md).

---

## Current State Summary

GAIA is a functional AI assistant with a working RLM (Recursive Language Model) loop,
persistent Guile REPL environment, safety validation, trajectory logging, and LiteLLM integration.
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

---

## Phase 1 — RLM Core Improvements & Homoiconicity 🔧

Hardening the agentic loop to handle the "parenthesis blindness" of smaller models (Gemma 4, Ministral)
and leveraging Lisp's code-as-data nature.

### Conversation & Context

- [ ] **Chat History (Conversation Continuity)** — Maintain a sliding window of condensed
  `(user, query) → (assistant, FINAL_answer)` pairs across CLI interactions.
  Each new `<query>` receives context from previous exchanges. Add `/clear` command to reset.
  *(Priority: HIGH — daily-use impact)*

- [ ] **Context Pruning** — If the model makes 3+ consecutive syntax/logic errors,
  prune failed attempts from the transcript and replace with a compact summary
  (e.g. `[System: Too many errors, history cleared. Write simpler code]`)
  to prevent "doom loops".

- [ ] **Bailout Mechanism** — If confidence drops drastically or the error loop persists too long,
  pause the main loop and spawn a diagnostic sub-agent to identify the logical problem.

### Code Robustness

- [ ] **Auto-healing (Syntax Self-Repair)** — Instead of rejecting code with missing parentheses,
  programmatically close unmatched `)` before calling `eval`. Use the existing
  `analyze-parentheses` function to detect and fix simple cases.

- [ ] **High-level Standard Library for LLM** — Add ready-made higher-order procedures to `tools.scm`
  to offload the model from writing complex nested loops:
  - `(read-files '("A" "B"))` — batch file reading
  - `(patch-file path old-string new-string)` — in-place string replacement in files
  - `(map-files dir pattern proc)` — apply procedure to matching files

### Homoiconicity (Code-as-Data)

- [ ] **Code Instrumentation & Auto-Logging** — Automatically rewrite LLM-generated code
  to wrap function calls in error handlers or performance loggers using Scheme macros.

- [ ] **G-Expressions ("Context Teleportation")** — Use GNU Guix's G-expressions (`#~`)
  to serialize variable contexts and modules when spawning sub-agents,
  solving the data transfer problem in `delegate` blocks.
  Currently sub-agents cannot access the parent's Scheme variables.

- [ ] **The Self-Modifying Agent** — Allow GAIA to refactor its own `rlm-loop`
  at runtime by treating the loop logic as a mutable S-expression.

---

## Phase 2 — Headless Architecture & Terminal UX 🏗️

Transition from monolith to a modern client-server architecture
inspired by tools like Claude Code / Cline.

### Architecture

- [ ] **Headless GAIA (Client-Server Split)** — Rebuild `run-gaia.scm` so the engine
  runs as a background server (UNIX sockets or local HTTP/JSON-RPC).
  The CLI becomes a thin client that communicates with the server.

- [ ] **Response Streaming (SSE)** — Switch LiteLLM calls to `("stream" . #t)` mode
  and stream tokens to the frontend for real-time character-by-character display.

### Terminal Client

- [ ] **Native CLI Client (Rust + `ratatui`)** — Build a fast, native terminal client.
  The client handles only rendering: file trees, Markdown formatting,
  async "thinking" spinners. No business logic.

### Safety & UX

- [ ] **Human-in-the-Loop Sandbox** — Modify the AST analyzer in `executor.scm`:
  instead of unconditionally blocking banned primitives (like `delete-file`),
  send a confirmation request to the CLI client:
  *"Agent wants to delete file X. Allow? [Y/N]"*.

- [ ] **Auto-Scaffolding** — On agent startup in a directory, silently run a lightweight
  `(list-files)` (respecting `.gitignore`) and inject the directory map
  into the system prompt for immediate spatial awareness.

- [ ] **Deterministic Replay** — Replay saved trajectory files offline without API costs
  for debugging and demonstration purposes.

---

## Phase 3 — Continuous Learning (Fine-Tuning & Data) 🧠

Closing the self-improvement loop where GAIA learns from its own mistakes,
as outlined in [training_spec.md](training_spec.md) and [fine_tuning_guide.md](fine_tuning_guide.md).

### Data Pipeline

- [ ] **Trajectory Cleaning (Compact Logging)** — Modify `curator.scm` to strip
  dead-end attempts and reasoning errors before writing to `.jsonl`,
  keeping only the ideal path from problem to final working code.

- [ ] **AST-based Training (Code-as-Data)** — Instead of logging textual code corrections
  for training, log the evolution of AST structure (how the model improved logic step by step).

### Training Infrastructure

- [ ] **Training Script (`make learn`)** — Implement the actual Python training script
  (Unsloth/QLoRA) and wire it into the Makefile. Currently `make learn` is a stub.

- [ ] **Champion/Challenger System** — After training a new adapter:
  run benchmark → compare with current model → promote if better.

- [ ] **Hot-Swap Adapters** — Automatically reload LiteLLM config after training
  to serve the newly fine-tuned model without manual restart.

---

## Phase 4 — Long-term Vision 🚀

### Guix Integration

- [ ] **Guix Container Isolation** — Execute AI-generated code in true
  `guix shell --container` ephemeral environments for bit-reproducible isolation.

### Web Interface

- [ ] **WebUI in Guile Hoot (WASM)** — After stabilizing the Headless server,
  build a web dashboard entirely in Scheme via Guile Hoot.
  Used for deep RLM tree monitoring, session management,
  and browsing trajectory databases before sending them to training.

### Research Directions

- [ ] **Tiny Recursive Model (TRM)** — Explore recursive architectures
  ([arxiv:2510.04871](https://arxiv.org/abs/2510.04871))
  for drastically reduced VRAM requirements via looped layer matrices.

- [ ] **MLIR/IREE Compilation** — Compile trained models to optimized
  hardware-specific artifacts for inference without PyTorch overhead.
  See: [MLIR](https://mlir.llvm.org/), [IREE](https://iree.dev/),
  [TVM](https://tvm.apache.org/).

---

## References

- RLM Paper: https://arxiv.org/abs/2512.24601
- RelayLLM: https://arxiv.org/pdf/2601.05167
- FusionRoute: https://arxiv.org/pdf/2601.05106
- TRM: https://arxiv.org/abs/2510.04871 ([source](https://github.com/SamsungSAILMontreal/TinyRecursiveModels))
