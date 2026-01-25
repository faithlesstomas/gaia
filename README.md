# GAIA: GNU AI Assistant

**GAIA** (GNU AI Assistant) is a next-generation system operator designed for the GNU Guix ecosystem.
It implements the **Recursive Language Model (RLM)** paradigm of inference strategy, allowing an AI agent to solve complex,
large-scale system tasks by programmatically investigating the environment rather than merely "reading" it.

The RLM idea comes from this paper: https://arxiv.org/abs/2512.24601

This implementation test's whether it make sense to implement RLM in functional and homoiconic language like Guile, a GNU Scheme derivative.
Hopefully it will evolve in a general purpose AI Assistant useful in GNU Guix and/or Linux ecosystem.

## The Philosophy: Intelligence as an Operator

Traditional AI assistants fail when faced with massive data (e.g., 1GB log files) due to context window limits.
GAIA solves this by treating the LLM as a **planner** and the system as a **programmatic environment**.

* **Don't Read, Investigate:** Instead of uploading files, GAIA generates Guile Scheme code to explore them locally.
* **Recursive Decomposition:** Complex tasks are broken down into sub-tasks and handled by recursive agent calls.
* **Functional Isolation:** Every investigative step runs in a bit-reproducible, isolated `guix shell --container`.

## Architecture

GAIA acts as the "Hands" (Scheme/Guix) for a "Brain" (LLM) hosted by the **RAI Server**.

1. **RAI (Python/FastAPI):** The Intelligence Gateway. Manages LLM providers (Gemini, GPT-5, Qwen) and system prompts.
2. **GAIA (Guile Scheme):** The System Core. Handles the RLM loop, code parsing, and recursive logic.
3. **GNU Guix:** The Execution Layer. Provides safe, isolated, and reproducible sandboxes for AI-generated code.

## Key Features

* **RLM Toolkit:** Native Guile implementation of the Recursive Language Model paradigm.
* **Guix Sandboxing:** Securely run AI-generated scripts in ephemeral containers.
* **Deterministic Replay:** Debug system behavior offline by replaying saved AI trajectories without API costs.
* **Self-Improvement Loop:** Automatically log and curate "Success" vs "Failure" datasets for local fine-tuning (Gemma/Qwen).

## Getting Started

### Prerequisites

* [GNU Guix](https://guix.gnu.org/)
* A running [RAI Server](https://gitlab.com/tk-lab1/ai/rai)

### Installation

Clone the repository and enter the environment:

```bash
git clone https://gitlab.com/tk-lab1/ai/gaia
cd gaia
```

### Usage

**1. Ensure RAI Server is Running:**
GAIA acts as a client. Ensure the [RAI Server](https://gitlab.com/tk-lab1/ai/rai) is running locally or accessible via network.
```bash
# In a separate terminal (if running locally):
git clone https://gitlab.com/tk-lab1/ai/rai
cd rai
python -m venv .venv
sourve .venv/bin/activate
python -m pip install -e .
# Read RAI project README or or doc for details of installing different LLM providers/adapters and their dependencies,
# eg. for local ollama you need to install ollama server as well.
rai config # setup server configuration
rai serve
curl http://localhost:8000/health
```

**2. Start GAIA Agent (Interactive Mode):**
```bash
make run
```

**3. Run Verification Tests:**
```bash
# Run Unit Tests
make test-units

# Run RLM PoC (Sandbox verification)
make test-rlm
```

**3. Curate Data for Fine-tuning:**

```bash
make dataset

```

## The Learning Loop

GAIA doesn't just work; it grows. Every interaction is stored in `trajectories.jsonl`.

* **Logger:** Captures prompts, generated code, and execution results.
* **Curator:** Filters successful interactions into a high-quality dataset.
* **Goal:** Fine-tune smaller, local models to match or exceed frontier model performance on Guix-specific tasks.

## License

GAIA is part of the GNU ecosystem and is released under the **GPLv3+ License**.

## Roadmap: Leveraging Homoiconicity (Code-as-Data)

The choice of Guile Scheme (a homoiconic Lisp dialect) is not accidental. It allows GAIA to treat its own code as data, enabling features impossible in Python/Javascript architectures.

*   [x] **Static Safety Validator:**
    *   **Concept:** Parse LLM-generated code as an AST (Abstract Syntax Tree) before execution. recursively check for banned primitives (e.g., `system*`, `delete-file`) even in deeply nested expressions.
    *   **Status:** *Implemented* (see `validate-safety` in `executor.scm`).

*   [ ] **Code Instrumentation & Auto-Logging:**
    *   **Concept:** Automatically rewrite user code to wrap function calls in error handlers or performance loggers without asking the LLM to do so.

*   [ ] **G-Expressions ("Context Teleportation"):**
    *   **Concept:** Use GNU Guix's G-expressions (`#~`) to serialize entire variable contexts and modules when spawning sub-agents, solving the "data transfer" problem in RLM.

*   [ ] **The Self-Modifying Agent:**
    *   **Concept:** Allow GAIA to "refactor" its own cognitive loop (`rlm-loop`) at runtime by treating the loop logic as a mutable list.

*   [ ] **Persistent Thought Environment (REPL):**
    *   **Concept:** Maintain a long-running Guile REPL where the agent defines helper functions in Step 1 and reuses them in Step 10, mimicking human memory.
