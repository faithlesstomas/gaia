# GNU AI Assistant (GAIA)


### A Reference Implementation of the General Cognitive Architecture Specification


**GAIA** is a local-first reference implementation of the [General Cognitive Architecture Specification (GCAS)](gcas.md).
It combines persistent cognitive state, explicit epistemic provenance, a bounded global workspace, heterogeneous processors,
and a reproducible execution environment built in **GNU Guile**. It is designed for researchers and engineers who require
strict reproducibility, mathematical rigor, safe execution, and data privacy when integrating Large Language Models (LLMs).

Thanks to the Guile language, GAIA treats code as data (homoiconicity) to eliminate LLM hallucinations,
enforce mathematical logic, and guarantee strict white-box auditability.

As a neuro-symbolic AI engine, GAIA bridges the gap between probabilistic Large Language Models (LLMs)
and rigorous, deterministic symbolic reasoning. It achieves this by mapping continuous LLM workspace 
activations (J-space) directly to discrete symbolic actors (Goblins AtomSpace) and provers (Lean 4).


## Core Architecture & Why GNU Guile?

[![License: GPL v3](https://shields.io)](https://gnu.org)
[![Language: Scheme/Lisp](https://shields.io)](https://gnu.org)
[![Compiler Stack: MLIR/IREE](https://shields.io)](https://llvm.org)

While most AI tools are written in Python, Gaia utilizes **GNU Guile** (Scheme/Lisp). This is a deliberate architectural choice:
* **Homoiconicity (Code is Data):** Scheme's macro system and homoiconic nature make it the ultimate language for AI-generated code.
  The LLM can generate ASTs (Abstract Syntax Trees) that are safely evaluated, transformed, and sandboxed.
* **The GNU Guix Connection:** Guile is the foundation of GNU Guix. GAIA aims to leverage this to allow the LLM to spin up temporary,
  bit-reproducible containers, run physical simulations (e.g., N-body, molecular dynamics) in secure manner.

## Cognitive architecture

GCAS, not an individual LLM or agent loop, is GAIA's architectural source of truth. The system is a recurrent, event-driven
process connecting specialized processors through explicit Cognitive Objects, Cognitive State, a selectively admitting Global
Workspace, memory, Cognitive Control, and observable execution.

```text
Question / Environment → Cognitive Objects → Workspace competition
       ↑                         ↓                    ↓
 Memory / Evidence ← Cognitive State ← processor proposals
                                      ↓
                   Cognitive Control → approved Action → REPL / sandbox
                                      ↓
                              Result / Failure / Reflection
```

An LLM is a **Generative Cognition** processor: its outputs begin as hypotheses, not accepted knowledge. The Guile REPL and
sandbox are **Execution / Investigation** processors: they expose authoritative environment observations and reproducible results.
Planning, verification, memory, and control remain separate functions. See [gcas.md](gcas.md) for the normative specification.

## RLM as a compatibility and investigation capability

GAIA originated as an implementation of the **Recursive Language Model (RLM)** paradigm: using an LLM and a persistent REPL to
investigate large inputs programmatically rather than merely reading them. That capability remains useful, especially for long-context
investigation, but it is no longer GAIA's cognitive architecture or main control loop.


The RLM idea comes from this paper: https://arxiv.org/abs/2512.24601

### The investigation capability

Traditional AI assistants fail when faced with massive data (e.g., 1GB log files) due to context window limits. GAIA retains a
programmatic investigation capability through its Guile REPL:

* **Don't Read, Investigate:** Instead of uploading files, GAIA generates Guile Scheme code to explore them locally.
* **Scoped decomposition:** A Cognitive Control policy may delegate a bounded investigation to a sub-process when it improves progress.
* **Functional Isolation:** Investigative steps run in sandboxed environments with AST-level safety validation.
## Architecture

GAIA is designed with a **Kernel + Pluggable Modules** architecture, built on top of a **Client-Server model**:

* **GAIA Kernel:** The GCAS-Core engine coordinating Cognitive Objects, State, Workspace, Control, memory, processors, and auditable execution.
* **Extension Modules:** Opt-in plugins extending the kernel to other domains (Wayland window managers, Lean 4 provers, local voice models, etc.) without mutating the system core.
* **Client-Server Topology:** Native Rust CLI client connected to a headless Guile Scheme server over UNIX sockets using S-expressions.
* **LiteLLM Gateway:** API proxy routing prompts to Ollama, Gemini, or other local/remote backends.
* **GNU Guix Layer:** Execution environment providing reproducible sandboxes (`guix shell`) for AI-generated code.


## Key Features

* **Client-Server Architecture:** Native Rust CLI client connected to a headless Guile Scheme engine over UNIX sockets.
* **GCAS cognitive kernel:** Event-driven coordination of generative, deliberative, memory, and execution processors.
* **Investigation toolkit:** Persistent Guile REPL and sandbox for RLM-style exploration of large or external data.
* **Safety Validation:** AST-level recursive scan of LLM-generated code for banned primitives before execution.
* **Multi-Model Support:** Hot-swappable LLM backends via LiteLLM (Gemma, Ollama, Gemini, Anthropic).
* **Thinking Mode:** Native reasoning support for models with `<|think|>` tags (Gemma 4).
* **Self-Improvement Loop:** Trajectory logging → dataset curation → fine-tuning pipeline.
* **Live Monitoring:** Real-time trajectory viewer for debugging agent reasoning.
* **Neuro-Symbolic J-space Alignment:** Proactive safety monitoring and working-memory synchronization mapping LLM internal activations (J-space) to symbolic Goblins actors and Lean 4 provers.

## Getting Started

### Prerequisites

* [GNU Guix](https://guix.gnu.org/)
* An active OpenAI-compatible endpoint (like local `uv run litellm`)

### Installation

Clone the repository and enter the environment:

```bash
git clone https://gitlab.com/tk-lab1/ai/gaia
cd gaia
```

**Configure LiteLLM:**
GAIA uses LiteLLM as an API proxy. Before starting the server, create your configuration file from the provided template:
```bash
cp litellm_config.yaml.template litellm_config.yaml
# Edit litellm_config.yaml with your preferred local or remote models and API keys
```

### Running with Docker / Podman (Alternative)

If you prefer a self-contained installation without installing Guix or Rust on your host machine, you can run GAIA and LiteLLM together using Docker Compose:

1. **Start the containers:**
   ```bash
   # Run with host UID/GID env to avoid file permission issues in mounts
   GAIA_UID=$(id -u) GAIA_GID=$(id -g) docker-compose up --build -d
   ```
   This command starts:
   - A reproducible `gaia-server` container based on GNU Guix.
   - A `litellm` gateway container on port 4000.
   - A shared mount for `/tmp/gaia.sock`, making the server socket accessible on your host machine.

2. **Accessing the CLI:**
   You can run the native client binary locally on your host (`./bin/gaia`), and it will connect directly to the containerized server via `/tmp/gaia.sock`.
   Alternatively, you can run the client inside the container:
   ```bash
   docker-compose exec -u $(id -u):$(id -g) gaia-server guix shell -m guix.scm -- cargo run --manifest-path src/gaia-cli/Cargo.toml
   ```

3. **Connecting to Host Services (e.g. Ollama):**
   If Ollama is running on your host machine, LiteLLM running inside Docker cannot connect to it using `localhost`. You must edit `litellm_config.yaml` to change `http://localhost:11434` to `http://host.docker.internal:11434`.

### Usage

**1. Start the Headless Server (Backend):**
GAIA runs as a background process listening on `/tmp/gaia.sock`. Starting the server will automatically start the LiteLLM proxy if it isn't running.
Open a terminal and run:
```bash
./bin/gaia-server
```
*Note: You can override the default model using `GAIA_MODEL=<model> ./bin/gaia-server`*

**2. Start the Interactive CLI (Frontend Client):**
In a separate terminal, connect to the server using the native Rust client:
```bash
./bin/gaia
```

**3. Run Verification Tests:**
```bash
# Run Unit Tests
make check

# Run LLM Tool-Use Check
make test-tool-use

# Run REPL investigation compatibility check
make test-rlm
```

**4. Curate Data for Fine-tuning:**

```bash
make dataset

```

## Learning and evolution

GAIA doesn't just work; it grows. Every interaction is stored in `trajectories.jsonl`.

* **Logger:** Captures prompts, generated code, and execution results.
* **Curator:** Filters successful interactions into a high-quality dataset.
* **Goal:** Fine-tune smaller, local models to match or exceed frontier model performance on Guix-specific tasks.
* **Guide:** See [fine_tuning_guide.md](fine_tuning_guide.md) for instructions.

## Legacy RLM benchmark results

We tested GAIA's RLM core using a "Needle in a Haystack" task (finding a key in a 10MB text file).

*   **Setup:** Ministral-3b model, local execution, 10MB haystack.
*   **Result:** The RLM loop successfully orchestrated the investigation,
    attempting to write Scheme scripts to read the file.
*   **Observation:** The infrastructure (Error Handling, Retry Logic, Completion Signals) worked perfectly.
    *   Syntax errors from the model were caught and fed back.
    *   The model attempted to self-correct based on feedback.
*   **Limitation:** The small 3B model struggled to generate syntactically correct Guile Scheme
    for file I/O (often missing parentheses or modules), leading to a retry loop.
    This highlights the need for larger/better-tuned models for code generation, but validates the *system architecture*.

## License

GAIA is part of the GNU ecosystem and is released under the **GPLv3+ License**. See [LICENSE](LICENSE) for details.

## Roadmap

See **[ROADMAP.md](ROADMAP.md)** for the full development plan. The project is organized around:
- **GCAS-Core migration** — Cognitive Objects, State, Workspace, Control, memory, and auditable execution, with the legacy RLM loop retained only as an investigation compatibility layer.
- **Showcase Benchmarks** — GAIA-SysOps (system administration tasks) and GAIA-Math (programming/logical challenges) to validate the model's evolution.
- **Extension Modules** — Decoupled domains: `gaia-accel` (tensor compiling), `gaia-io` (voice/vision), `gaia-desktop` (COSMIC/Emacs), `gaia-os` (transactional self-healing), `gaia-proof` (Lean 4/Z3), and `gaia-sci` (RAG/Hyperon FFI).

---
*GAIA is under active development. If you are interested in supporting this digital commons project, please reach out.*
