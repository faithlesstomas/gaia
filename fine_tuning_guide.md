# GAIA Fine-Tuning Guide (Deep Supervision)

This guide explains how to use GAIA's self-improvement loop to fine-tune local LLMs (like Ministral-3b, Gemma-4/3) for better performance on GNU Guix tasks.

## 1. Concepts: LoRA, QLoRA, and Unsloth

To train LLMs locally on consumer hardware, we use efficient techniques:

### **LoRA (Low-Rank Adaptation)**
Instead of retraining all 7 billion or 4 billion parameters (which requires massive VRAM), LoRA freezes the main model and trains only tiny "adapter" matrices inserted into the model layers.
*   **Pros:** Fast, low VRAM usage, checkpoint is small (~100MB).
*   **Cons:** Slightly less flexible than full fine-tuning (but sufficient for most tasks).

### **QLoRA (Quantized LoRA)**
QLoRA takes efficienty further by loading the **base model in 4-bit precision** (using NF4 format) while training the LoRA adapters in 16-bit.
*   **Pros:** Allows fine-tuning 7B/4B models on a single 12GB GPU (or even smaller).
*   **Impact:** This is the standard for local LLM tuning today.

### **PyTorch & LoRA Inference Overhead (Performance Issues)**
While the standard training stack (PyTorch + HuggingFace PEFT) with LoRA injection executes the *Proof of Concept* and trains the model brilliantly, inference (text generation) using this stack is drastically slow compared to compiled C++ stacks (e.g., Llama.cpp / Ollama) due to several reasons:
1. **Autoregressive Loop in Python:** The overhead of invoking heavy functions within a Python loop for each generated token.
2. **Compilation & Hardware (AMD ROCm):** Libraries like PyTorch have dynamic frameworks (TorchDynamo/SDPA) which can run asynchronously faster on GPUs. However, on smaller chips like RDNA3 APUs, these often lead to environment freezes and HIP MES errors.
3. **No KV Cache:** To stabilize model operation (bypassing faults like *unspecified launch failure*), we are forced to disable dynamic cache tables (`use_cache=False`), which forces the model to iteratively recalculate sequences from the beginning for each token. This wastes 95% of processing power.

---

## 2. Architecture: Where to Train?

### Recommendation: **Train in Python Node, Run in GAIA (Guile) via LiteLLM**

| Component | Responsibility | Technology |
|-----------|----------------|------------|
| **GAIA** | **Data Generation**. Runs the RLM loop, encounters errors, creates `dataset-success.jsonl`. | Guile Scheme |
| **Training Node** | **Training & Validation**. Manages the GPU, runs the PyTorch training loop. | Python (PyTorch/Transformers) |
| **IREE / Ollama** | **Production Inference**. Exported models should be compiled here behind LiteLLM Proxy. | MLIR / Llama.cpp / LiteLLM |

**Future Vector - MLIR/IREE instead of PyTorch for Execution**
*   **Maturity:** Keeping in mind the PyTorch optimization issues described, the trained LoRA layer should be permanently merged (`merge_and_unload()`) into the base weights (e.g., in `.vmfb` or `.gguf` format), and the inference workload loaded onto the optimal MLIR/IREE compilation engine.
*   **Strategy:** Use PyTorch strictly to *train* the model as an experimental refinement with the PEFT flag. Once the experiment is complete, compile it using external toolchains to achieve 10x higher speed and utilize KV Cache without crashes for the GAIA architecture.

---

## 3. The Data Pipeline

1.  **Interaction**: User interacts with GAIA (via `make run` or `make benchmark`).
2.  **Logging**: Every step is logged to `trajectories.jsonl`.
3.  **Curation**: `make dataset` runs `curator.scm`.
4.  **Filtering**:
    *   **Success**: Sessions ending with `FINAL()` are saved to `dataset-success.jsonl`.
    *   **Failure**: Failed attempts are saved to `dataset-failure.jsonl`.

## 4. How to Fine-Tune (Python Module)

We assume you will implement a training module in a **Python Environment** located at `~/scratch/AI/training`.

### Step 1: Install Unsloth in Environment

```bash
cd ~/scratch/AI/training
pip install "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git"
pip install --no-deps "xformers<0.0.26" trl peft accelerate bitsandbytes
```

### Step 2: Run Training (Conceptual Script)

Create a script `train_gaia.py`:

```python
from unsloth import FastLanguageModel
from trl import SFTTrainer
from transformers import TrainingArguments
from datasets import load_dataset

# 1. Load Model
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name = "google/gemma-2-4b",
    max_seq_length = 4096,
    dtype = None,
    load_in_4bit = True,
)

# 2. Add LoRA
model = FastLanguageModel.get_peft_model(
    model,
    r = 16,
    target_modules = ["q_proj", "k_proj", "v_proj", "o_proj"],
    lora_alpha = 16,
    lora_dropout = 0,
    bias = "none",
)

# 3. Load GAIA Dataset
dataset = load_dataset("json", data_files="path/to/gaia/dataset-success.jsonl", split="train")

# 4. Train
trainer = SFTTrainer(
    model = model,
    tokenizer = tokenizer,
    train_dataset = dataset,
    dataset_text_field = "text",
    max_seq_length = 4096,
    args = TrainingArguments(
        per_device_train_batch_size = 2,
        gradient_accumulation_steps = 4,
        warmup_steps = 5,
        max_steps = 60,
        learning_rate = 2e-4,
        fp16 = not is_bfloat16_supported(),
        bf16 = is_bfloat16_supported(),
        logging_steps = 1,
        output_dir = "outputs",
        optim = "adamw_8bit",
    ),
)
trainer.train()

# 5. Save Adapter
model.save_pretrained("gaia-lora-adapter")
```

### Step 3: Load Adapter in Ollama/LiteLLM

Once trained, merge to GGUF and tell LiteLLM or Ollama to load the model with the new adapter:

```yaml
# Example LiteLLM config change
model_list:
  - model_name: gemma4-finetuned
    litellm_params:
      model: ollama/gemma4-finetuned
      api_base: http://localhost:11434
```

---

## 5. Future Research Paths (Note)

For the next educational cycles of GAIA, exploring the idea of the **TRM (Tiny Recursive Model)** is worth considering.
- According to the publication [https://arxiv.org/abs/2510.04871](https://arxiv.org/abs/2510.04871), recursive architectures offer the capability to drastically reduce VRAM requirements by recursively utilizing the same small, looped layered matrices.
- Deploying a model compiled with IREE in tandem with TRM would provide a potentially phenomenal opportunity to implement a *hardware-accelerated agent capable of native background learning without PyTorch overheads*.
- *Next Steps:* Add prototyping of a compilation mechanism for novel TRM graphs within the HuggingFace ecosystem to the roadmap.
