# GCAS MVP live conversation evaluation — qwen3.5-4b

## Decision

**PASS** for the bounded two-turn conversational-continuity gate on
2026-08-30. This result supplies the live conversation evidence for the GAIA
MVP. It does not supply the separate repeated executable-capability baseline.

## Resource envelope

- LiteLLM model alias: `qwen3.5-4b`
- Ollama model: `qwen3.5:4b`
- reported parameters: 4.7B
- quantization: `Q4_K_M`
- model count before the run: 0
- maximum simultaneously resident models during the run: 1
- resident model during the run: `qwen3.5:4b`
- model count after explicit unload: 0
- thinking: disabled
- per-call timeout: 300 seconds
- operator approval: explicit

The local LiteLLM process was started only for the evaluation and stopped
afterward. Ollama was queried through `/api/ps` before and after the run; no
other model was resident.

## Command

```sh
GAIA_EVAL_MODELS=qwen3.5-4b \
GAIA_EVAL_MODEL_PARAMETERS_B=4.7 \
GAIA_EVAL_MAX_MODEL_PARAMETERS_B=4.7 \
GAIA_EVAL_RESOURCE_APPROVED=1 \
GAIA_EVAL_VERBOSE=2 \
GAIA_LLM_TIMEOUT_SECONDS=300 \
GAIA_CONVERSATION_EVAL_OUTPUT=/tmp/gcas-conversation-qwen3.5-4b.json \
make gcas-live-conversation-eval
```

## Result

The first turn asked the assistant to retain `GAIA-MVP-7319`. The runner then
created a fresh Cognitive Session over the same durable Memory and asked for
the identifier. The second response was exactly `GAIA-MVP-7319`.

| Check | Result |
|---|---|
| both turns completed | pass |
| nonce present in restored Memory projection | pass |
| nonce recalled in model response | pass |
| bounded projection | pass; 814 characters in turn two |
| projection marked as non-transcript replay | pass |
| provider protocol history | pass; zero messages |
| assistant content remains `HYPOTHESIS` / `UNVERIFIED` | pass |
| separate Claims use `DELIVERY_ONLY` verification | pass |

Turn-one latency was 5738.2 ms and turn-two latency was 2357.5 ms. Both Goals
ended as `COMPLETED` with one terminal outcome. The trace showed Goal creation,
Memory retrieval, Workspace rounds and broadcasts, hypothesis creation,
delivery Evidence, scoped Claim verification, and Goal completion.

## Boundary

This is a single-model architectural continuity check. It demonstrates that a
real model can use restored, bounded GCAS Memory without provider transcript
history. It does not establish open-ended memory quality, factual accuracy,
MATH-500 competence, or readiness of the five executable capabilities. Those
capabilities still require the repeated eval-v2 matrix.

The live target is local-only. Both its Makefile target and its Scheme runner
fail closed when `CI` is present, and no CI/CD job invokes it.
