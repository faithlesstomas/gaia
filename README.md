# GAIA: GNU AI Assistant

**GAIA** (GNU AI Assistant) is a next-generation system operator designed for the GNU Guix ecosystem. 
It implements the **Recursive Language Model (RLM)** paradigm, allowing an AI agent to solve complex, 
large-scale system tasks by programmatically investigating the environment rather than merely "reading" it.

## 🧠 The Philosophy: Intelligence as an Operator

Traditional AI assistants fail when faced with massive data (e.g., 1GB log files) due to context window limits. 
GAIA solves this by treating the LLM as a **planner** and the system as a **programmatic environment**.

* **Don't Read, Investigate:** Instead of uploading files, GAIA generates Guile Scheme code to explore them locally.
* **Recursive Decomposition:** Complex tasks are broken down into sub-tasks and handled by recursive agent calls.
* **Functional Isolation:** Every investigative step runs in a bit-reproducible, isolated `guix shell --container`.

## 🏗️ Architecture

GAIA acts as the "Hands" (Scheme/Guix) for a "Brain" (LLM) hosted by the **RAI Server**.

1. **RAI (Python/FastAPI):** The Intelligence Gateway. Manages LLM providers (Gemini, GPT-5, Qwen) and system prompts.
2. **GAIA (Guile Scheme):** The System Core. Handles the RLM loop, code parsing, and recursive logic.
3. **GNU Guix:** The Execution Layer. Provides safe, isolated, and reproducible sandboxes for AI-generated code.

## 🛠️ Key Features

* **RLM Toolkit:** Native Guile implementation of the Recursive Language Model paradigm.
* **Guix Sandboxing:** Securely run AI-generated scripts in ephemeral containers.
* **Deterministic Replay:** Debug system behavior offline by replaying saved AI trajectories without API costs.
* **Self-Improvement Loop:** Automatically log and curate "Success" vs "Failure" datasets for local fine-tuning (Gemma/Qwen).

## 🚦 Getting Started

### Prerequisites

* [GNU Guix](https://guix.gnu.org/)
* A running [RAI Server](https://gitlab.com/tk-lab1/ai/rai)

### Installation

Clone the repository and enter the environment:

```bash
git clone <repository-url>
cd gaia
guix shell
```

### Usage

**1. Ensure RAI Server is Running:**
GAIA acts as a client. Ensure the [RAI Server](https://gitlab.com/tk-lab1/ai/rai) is running locally or accessible via network.
```bash
# In a separate terminal (if running locally):
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

## 📈 The Learning Loop

GAIA doesn't just work; it grows. Every interaction is stored in `trajectories.jsonl`.

* **Logger:** Captures prompts, generated code, and execution results.
* **Curator:** Filters successful interactions into a high-quality dataset.
* **Goal:** Fine-tune smaller, local models to match or exceed frontier model performance on Guix-specific tasks.

## 📜 License

GAIA is part of the GNU ecosystem and is released under the **GPLv3+ License**.
