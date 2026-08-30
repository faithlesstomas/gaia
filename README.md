# GNU AI Assistant (GAIA)

[![GitHub CI](https://github.com/faithlesstomas/gaia/actions/workflows/ci.yml/badge.svg)](https://github.com/faithlesstomas/gaia/actions/workflows/ci.yml)


### A Work-in-Progress Reference Implementation of the General Cognitive Architecture Specification


**GAIA** is a local-first project implementing the [General Cognitive Architecture Specification (GCAS)](gcas.md).
The current codebase provides a memory-backed conversational assistant, persistent cognitive state, explicit epistemic provenance, a bounded Workspace substrate,
processor contracts, and an auditable execution environment built in **GNU Guile**. Production `solve` is now assembled from
processors reacting through the Cognitive Bus. Production `solve` uses explicit Workspace competition rounds and bounded
feedback-driven replanning after failed actions or conflicts. A Goal may complete only through an independent verifier and a verified
Claim. The GCAS-Core 0.2 baseline conformance gate covers failure-first repair, persistence, budgets, interruption, and both supported
clients. This is architectural conformance, not general task competence: Fibonacci is the first registered production verifier,
while unsupported task classes deliberately terminate as `INCONCLUSIVE`.
Control-driven budget exhaustion now also reaches the client as a terminal response, including the three-failed-Action case that
previously left the CLI waiting. The current product milestone is the
[GAIA MVP — Persistent Verified Assistant](docs/gaia-mvp.md): a measurable
vertical slice combined with durable graph memory and longitudinal acceptance
tests, rather than immediate implementation of every GCAS extension.

Thanks to the Guile language, GAIA treats code as data (homoiconicity), enabling structural validation,
sandboxed evaluation, and white-box auditability. These mechanisms constrain generated code; they do not eliminate LLM errors.

GAIA aims to bridge probabilistic Large Language Models (LLMs) and deterministic symbolic reasoning.
The read-only NCSI/J-space path is implemented as an opt-in experimental
profile. Initial AtomSpace semantics—durable CO nodes, typed edges, traversal,
dependency invalidation, and supersession—are implemented over the transparent
local store. A Goblins actor backend, STI/LTI, Lean 4 integration, and write-side
neural intervention remain roadmap work.

## Evidence and implementation status

| Area | Status | Evidence and boundary |
|---|---|---|
| GCAS-Core 0.2 lifecycle | **Implemented baseline** | The model-free corpus passes 23/23 cases with zero hangs and false completions, including 5/5 repair paths and preflight rejection before execution; GCAS 0.3 uncertainty conformance is roadmap work. |
| Persistent GCAS assistant | **Implemented; live release gate pending** | Plain input is a bounded GCAS conversation. Typed user/assistant turns survive restart, prompts are reconstructed from bounded Memory with empty protocol history, and assistant prose remains `HYPOTHESIS`/`UNVERIFIED`. Five executable capabilities use production-v2 private behavioral harnesses. The repeated one-model live baseline is still required for release readiness. |
| NCSI/J-space observation path | **Experimental** | The versioned protocol, RAI UDS adapter, neural Observation COs, bounded Workspace proposals, fallback, and matched M5 harness are implemented. The 18-run SmolLM2 pilot supports `SHIP_EXPERIMENTAL`, not a causal or epistemic claim. |
| NCSI sidecar hardening and artifact replication | **In progress in RAI** | The clean-environment artifact reproduction/resource baseline and several operational M1–M3 gates remain open. |
| Goblins AtomSpace backend, STI/LTI, steering, formal proving, cross-task benchmark | **Roadmap** | These capabilities are not part of the current production claim. |

See the [GAIA MVP contract](docs/gaia-mvp.md), the
[capability and readiness matrix](docs/capability-matrix.md), the
[uncertainty implementation](docs/gcas-uncertainty.md), the
[deterministic evaluation report](docs/gcas-evaluation.md), the
[M5 evaluation](docs/evaluations/ncsi-smollm2-m5.md), its
[machine-readable summary](docs/evaluations/ncsi-smollm2-m5-summary.json), and
the [canonical NCSI milestone checklist](docs/ncsi-jlens-integration.md).


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

GCAS, not an individual LLM or agent loop, is GAIA's architectural source of truth. The target system is a recurrent,
event-driven process connecting specialized processors through explicit Cognitive Objects, Cognitive State, a selectively
admitting Global Workspace, memory, Cognitive Control, and observable execution.

```text
Question / Environment → Cognitive Objects → Workspace competition
       ↑                         ↓                    ↓
 Memory / Evidence ← Cognitive State ← processor proposals
                                      ↓
                   Cognitive Control → approved Action → REPL / sandbox
                                      ↓
                              Result / Failure / Reflection
```

In the current GCAS-Core 0.2 baseline `solve` path, LLM output begins as a hypothesis and sandbox execution crosses an explicit
Action/Result boundary. State and event traces are durable, and Memory, Generative, Planner, Execution, Deliberative, Answer,
Goal Verifier, and Control processors react through the Cognitive Bus. Control runs explicit Workspace rounds and
failure/conflict feedback can produce a revised hypothesis, Plan, and Action under bounded budgets. Successful execution remains
`INCONCLUSIVE` unless a task-specific independent verifier accepts the evidence. Verified evidence chains and explicit user
testimony are stored separately from chat transcripts and can be retrieved across turns. See
[the conformance audit](docs/gcas-core-conformance.md) for the exact scope,
[the prompt projection design](docs/gcas-prompt-projection.md) for what the model
currently receives, [the GCAS 0.2 research synthesis](docs/gcas-0.2-research-synthesis.md)
for the consolidated rationale, and [gcas.md](gcas.md) for the normative specification.

The normative specification is now GCAS 0.3. GAIA does not yet claim `GCAS-Uncertainty 0.3` conformance: its existing scalar CO
confidence and Workspace uncertainty fields are scheduling metadata, not calibrated posterior probabilities. The migration is tracked
in [ROADMAP.md](ROADMAP.md), with reviewable implementation slices and acceptance
criteria in [the GAIA MVP contract](docs/gaia-mvp.md#gcas-03-implementation-plan).

Neither ordinary conversation nor production `solve` replays chat history to
the model. Normal input reconstructs a bounded conversational projection from
recent episodic turns and relevant structured Memory; the delivered prose stays
an unverified hypothesis. Production `solve`
sends a compact GCAS-specific Action contract plus a transient projection reconstructed
from the current Goal, admitted Workspace objects, selected structured Memory,
constraints, and—during repair—the latest Reflection. This avoids transcript
growth and removes the legacy `FINAL/CONFIDENCE` protocol from production
generation. Further phase-specific projection changes remain evaluation-driven.

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

* **GAIA Kernel:** The GCAS-Core engine containing Cognitive Objects, State, Workspace, Control, memory, processor contracts, and auditable execution.
* **Extension Modules:** Opt-in plugins extending the kernel to other domains (Wayland window managers, Lean 4 provers, local voice models, etc.) without mutating the system core.
* **Client-Server Topology:** Native Rust CLI client connected to a headless Guile Scheme server over UNIX sockets using S-expressions.
* **LiteLLM Gateway:** API proxy routing prompts to Ollama, Gemini, or other local/remote backends.
* **GNU Guix Layer:** Execution environment providing reproducible sandboxes (`guix shell`) for AI-generated code.


## Key Features

* **Client-Server Architecture:** Native Rust CLI client connected to a headless Guile Scheme engine over UNIX sockets.
* **GCAS substrate:** Per-Goal process lifecycle, round-based Workspace competition, Bus-attached recurrent production processors, durable CO/event state, structured memory, audited execution, and independently verified Goal completion.
* **Investigation toolkit:** Persistent Guile REPL and sandbox for RLM-style exploration of large or external data.
* **Safety Validation:** AST-level recursive scan of LLM-generated code for banned primitives before execution.
* **Multi-Model Support:** Hot-swappable LLM backends via LiteLLM (Gemma, Ollama, Gemini, Anthropic).
* **Thinking Mode:** Native reasoning support for models with `<|think|>` tags (Gemma 4).
* **Self-Improvement Infrastructure:** Trajectory logging and dataset curation foundations; governed closed-loop deployment remains roadmap work.
* **Live Monitoring:** Real-time trajectory viewer for debugging agent reasoning.
* **Neuro-Symbolic Integration:** Experimental read-only NCSI/J-space observations; symbolic actors, formal provers, and neural intervention remain roadmap work.

The default `gemma4:e2b` backend is a relatively small, tool-oriented model. Its
Guile syntax failures are a known competence limitation that predates the GCAS
migration. GAIA therefore distinguishes a correct control architecture from a
capable model: NCSI/J-space may later improve neural steering, while near-term
reliability work uses structured feedback, phase-aware prompt projections,
syntax preflight, high-level tools, and executable verifiers.

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

# Run the deterministic GCAS-Core contract showcase (not a production conformance test)
make gcas-showcase

# Run the model-free deterministic GCAS competence corpus
make gcas-eval

# Run the opt-in live-model matrix (uses GAIA_MODEL by default)
make gcas-live-eval

# Run the two-turn restart/recall gate for ordinary GCAS conversation
GAIA_EVAL_MODELS='<litellm-model-name>' \
GAIA_EVAL_MODEL_PARAMETERS_B=4 \
GAIA_EVAL_RESOURCE_APPROVED=1 \
GAIA_CONVERSATION_EVAL_OUTPUT=/tmp/gcas-conversation.json \
make gcas-live-conversation-eval

# Run the production GCAS-Core conformance gate, including CLI and Emacs protocol tests
make gcas-conformance

# Run all NCSI protocol, policy, evaluation, and real HTTP-over-UDS adapter tests
make test-ncsi
```

The deterministic commands above require no model server and are the public
reproducibility floor. Live calls have a 300-second per-call bound by default;
override it with `GAIA_LLM_TIMEOUT_SECONDS`. The live GCAS and NCSI evaluations are opt-in because
they require pinned model endpoints and, for NCSI, the separately installed RAI
neural dependencies and a checksummed lens artifact. To reproduce the published
M5 pilot, start the RAI sidecar at `$XDG_RUNTIME_DIR/rai/neural.sock`, then run:

```bash
GAIA_NCSI_SOCKET="$XDG_RUNTIME_DIR/rai/neural.sock" \
GAIA_NCSI_MODEL="HuggingFaceTB/SmolLM2-135M" \
GAIA_NCSI_LENS="smollm2-jlens-v1" \
GAIA_NCSI_REPEATS=2 \
GAIA_NCSI_LAYERS=12 \
GAIA_NCSI_MAX_NEW_TOKENS=12 \
GAIA_NCSI_EVAL_OUTPUT=/tmp/ncsi-m5.json \
make ncsi-eval
```

The exact revisions, artifact checksum, aggregate results, acceptance rule, and
limitations are recorded with the M5 report. Run-specific request IDs and
timings are intentionally not treated as stable golden values.

In the interactive CLI and Emacs client, plain text starts the memory-backed
GCAS conversation path. The client resumes the last logical session from
`.last_session` by default. Use `/chat <message>` explicitly for the same path,
`/solve <goal>` for one of the five executable and independently verified
capabilities, `/ask <query>` for legacy one-shot chat, `/investigate <query>` for the legacy
LLM–REPL investigation processor, `/eval <scheme>` for direct REPL execution,
`/cognitive-events` to inspect the session event trace, and `/cognitive-state`
(alias `/cognitive-objects`) to inspect the current Goal, Control budgets,
Workspace, Cognitive Objects, and structured Memory.

The server writes the same operational trace to `gaia-server.log`. Lines marked
`[GCAS][session-id]` record every semantic event together with the relevant CO
metadata, process and Control counters, and the pending/active Workspace IDs.
This trace is ordered before synchronous processor reactions, so causes appear
before the events they trigger. CO content is truncated to keep the log usable;
the complete durable graph remains available through `/cognitive-state` and
the session's `sessions/*.gcas-state.scm` file.

For example, these two ordinary turns use typed durable Memory rather than an
ever-growing LLM transcript:

```text
Mam na imię Tomasz.
Jak mam na imię?
```

Use `/cognitive-events` to see `ConversationTurnReceived`, `MemoryRetrieved`,
Workspace broadcasts, `HypothesisProposed`, `ResponseDeliveryVerified`, and
the terminal Goal events. Use `/cognitive-state` to inspect the corresponding
COs and epistemic statuses. The exact architecture and operational boundary are
described in [the conversation design](docs/gcas-conversation.md).

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
- **GCAS-Core migration** — Convert the implemented Cognitive Object, State, Workspace, Control, memory, and execution substrate into a recurrent event-driven production process; retain the legacy RLM loop only as an investigation compatibility layer.
- **Showcase Benchmarks** — GAIA-SysOps (system administration tasks) and GAIA-Math (programming/logical challenges) to validate the model's evolution.
- **Extension Modules** — Decoupled domains: `gaia-accel` (tensor compiling), `gaia-io` (voice/vision), `gaia-desktop` (COSMIC/Emacs), `gaia-os` (transactional self-healing), `gaia-proof` (Lean 4/Z3), and `gaia-sci` (RAG/Hyperon FFI).

---
*GAIA is under active development. If you are interested in supporting this digital commons project, please reach out.*
