
# GNU AI Assistant (GAIA)

**GAIA** is a local-First AI Assistant for any task in reproducible safe environment with REPL build in **GNU Guile**.
It is designed specifically for researchers and engineers who require strict reproducibility, 
mathematical rigor, safe execution and data privacy when integrating Large Language Models (LLMs) into their workflows.


## Core Architecture & Why GNU Guile?

While most AI tools are written in Python, Gaia utilizes **GNU Guile** (Scheme/Lisp). This is a deliberate architectural choice:
* **Homoiconicity (Code is Data):** Scheme's macro system and homoiconic nature make it the ultimate language for AI-generated code. 
  The LLM can generate ASTs (Abstract Syntax Trees) that are safely evaluated, transformed, and sandboxed.
* **The GNU Guix Connection:** Guile is the foundation of GNU Guix. GAIA aims to leverage this to allow the LLM to spin up temporary, 
  bit-reproducible containers, run physical simulations (e.g., N-body, molecular dynamics) in secure manner.

## Key ideas

GAIA implements the **Recursive Language Model (RLM)** paradigm of inference strategy, allowing an AI agent to solve complex,
large-scale system tasks by programmatically investigating the environment rather than merely "reading" it.


The RLM idea comes from this paper: https://arxiv.org/abs/2512.24601

### The Philosophy of RLM

Traditional AI assistants fail when faced with massive data (e.g., 1GB log files) due to context window limits.
GAIA solves this by giving the LLM an access to **programmatic environment** a GUile REPL in which it can operate
with this ideas in mind (and in system prompt as instructions):

* **Don't Read, Investigate:** Instead of uploading files, GAIA generates Guile Scheme code to explore them locally.
* **Recursive Decomposition:** Complex tasks are broken down into sub-tasks and handled by recursive agent calls.
* **Functional Isolation:** Investigative steps run in sandboxed environments with AST-level safety validation.
## Architecture

GAIA acts as the "Hands" (Scheme/Guix) for a "Brain" (LLM) hosted through an **OpenAI-compatible LLM Gateway**.

1. **LiteLLM / Proxy Server:** The Intelligence Gateway. Maps OpenAI-API calls to LLM providers 
   (Gemini, Local Ollama, Anthropic) handling context window limits and routing.
2. **GAIA (Guile Scheme):** The System Core. Handles the RLM loop, code parsing, and recursive logic.
3. **GNU Guix:** The Execution Layer. Provides safe, isolated, and reproducible sandboxes for AI-generated code.

## Key Features

* **RLM Toolkit:** Native Guile implementation of the Recursive Language Model paradigm with persistent REPL.
* **Safety Validation:** AST-level recursive scan of LLM-generated code for banned primitives before execution.
* **Multi-Model Support:** Hot-swappable LLM backends via LiteLLM (Gemma, Ollama, Gemini, Anthropic).
* **Thinking Mode:** Native reasoning support for models with `<|think|>` tags (Gemma 4).
* **Self-Improvement Loop:** Trajectory logging → dataset curation → fine-tuning pipeline.
* **Live Monitoring:** Real-time trajectory viewer for debugging agent reasoning.

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

### Usage

**1. Ensure LLM Proxy Server is Running:**
GAIA acts as a client. Ensure an LLM proxy server (like LiteLLM) is running locally or accessible via network.
```bash
# GAIA uses 'uv' environment manager to fetch and run LiteLLM seamlessly:
# Create litellm_config.yaml with your preferred local or remote models
uv run litellm --config litellm_config.yaml --port 4000
```

**2. Start GAIA Agent (Interactive Mode):**
```bash
make run
```

**3. Run Verification Tests:**
```bash
# Run Unit Tests
make check

# Run LLM Tool-Use Check
make test-tool-use

# Run RLM PoC (Sandbox verification)
make test-rlm
```

**4. Curate Data for Fine-tuning:**

```bash
make dataset

```

## The Learning Loop

GAIA doesn't just work; it grows. Every interaction is stored in `trajectories.jsonl`.

* **Logger:** Captures prompts, generated code, and execution results.
* **Curator:** Filters successful interactions into a high-quality dataset.
* **Goal:** Fine-tune smaller, local models to match or exceed frontier model performance on Guix-specific tasks.
* **Guide:** See [fine_tuning_guide.md](fine_tuning_guide.md) for instructions.

## Benchmark Results (Phase 3)

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

See **[ROADMAP.md](ROADMAP.md)** for the full development plan, including:
- Phase 1: RLM core improvements & homoiconicity (code-as-data)
- Phase 2: Headless architecture & terminal UX
- Phase 3: Continuous learning (fine-tuning & data pipeline)
- Phase 4: Long-term vision (Web UI, Guix containers, MLIR/IREE)

---
*GAIA is under active development. If you are interested in supporting this digital commons project, please reach out.*
