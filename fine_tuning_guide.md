# GAIA Fine-Tuning Guide (Deep Supervision)

This guide explains how to use GAIA's self-improvement loop to fine-tune local LLMs (like Ministral-3b, Gemma-2b) for better performance on GNU Guix tasks.

## 1. Concepts: LoRA, QLoRA, and Unsloth

To train LLMs locally on consumer hardware, we use efficient techniques:

### **LoRA (Low-Rank Adaptation)**
Instead of retraining all 7 billion parameters (which requires massive VRAM), LoRA freezes the main model and trains only tiny "adapter" matrices inserted into the model layers.
*   **Pros:** Fast, low VRAM usage, checkpoint is small (~100MB).
*   **Cons:** Slightly less flexible than full fine-tuning (but sufficient for most tasks).

### **QLoRA (Quantized LoRA)**
QLoRA takes efficienty further by loading the **base model in 4-bit precision** (using NF4 format) while training the LoRA adapters in 16-bit.
*   **Pros:** Allows fine-tuning 7B models on a single 12GB GPU (or even smaller).
*   **Impact:** This is the standard for local LLM tuning today.

### **Unsloth**
[Unsloth](https://github.com/unslothai/unsloth) is a library that optimizes the backpropagation mechanics of LoRA/QLoRA.
*   **Benefit:** Up to **2x faster training** and **60% less memory** usage than standard Hugging Face PEFT.
*   **Verdict:** We highly recommend using Unsloth for GAIA fine-tuning.

---

## 2. Architecture: Where to Train?

### Recommendation: **Train in RAI (Python), Run in GAIA (Guile)**

| Component | Responsibility | Technology |
|-----------|----------------|------------|
| **GAIA** | **Data Generation**. Runs the RLM loop, encounters errors, creates `dataset-success.jsonl`. | Guile Scheme |
| **RAI** | **Training & Inference**. Manages the GPU, loads Unsloth, runs the training loop. | Python (PyTorch/Unsloth) |

**Why not MLIR/IREE for training?**
*   **Maturity:** MLIR/IREE is excellent for **inference** deployment (running the model fast). However, the ecosystem for **training** LLMs (autograd, optimizers, LoRA implementations) is experimental compared to the mature PyTorch/Unsloth stack.
*   **Strategy:** Use PyTorch/Unsloth in RAI to *train* the model. Then, export the fine-tuned weights (merge LoRA) and compile them with IREE for *inference* if you want maximum performance.

---

## 3. The Data Pipeline

1.  **Interaction**: User interacts with GAIA (via `make run` or `make benchmark`).
2.  **Logging**: Every step is logged to `trajectories.jsonl`.
3.  **Curation**: `make dataset` runs `curator.scm`.
4.  **Filtering**:
    *   **Success**: Sessions ending with `FINAL()` are saved to `dataset-success.jsonl`.
    *   **Failure**: Failed attempts are saved to `dataset-failure.jsonl`.

## 4. How to Fine-Tune (via RAI)

We assume you will implement a training module in **RAI** located at `~/scratch/AI/rai`.

### Step 1: Install Unsloth in RAI

```bash
cd ~/scratch/AI/rai
pip install "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git"
pip install --no-deps "xformers<0.0.26" trl peft accelerate bitsandbytes
```

### Step 2: Run Training (Conceptual Script)

Create a script `train_gaia.py` in RAI:

```python
from unsloth import FastLanguageModel
from trl import SFTTrainer
from transformers import TrainingArguments
from datasets import load_dataset

# 1. Load Model
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name = "mistralai/Ministral-3b-v0.1",
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

### Step 3: Load Adapter in GAIA

Once trained, tell RAI to load the base model with the new adapter:

```bash
# Example RAI config change
model: "ministral-3b"
adapter: "gaia-lora-adapter"
```
