# GCAS live capability diagnostic — qwen3.5-4b

**Result:** `NOT_READY` on 2026-08-31.

This operator-approved diagnostic exercised all five production-v2 capabilities
with ten repetitions each through LiteLLM and a single resident Ollama model.
Ollama reported `qwen3.5:4b`, 4.7B parameters, Q4_K_M. No second model was
loaded during the evaluation, and Ollama reported an empty resident-model list
after the run.

## Results

| Capability | Passed | Success | Readiness threshold |
|---|---:|---:|---:|
| `arithmetic-42` | 5/10 | 50% | 80% |
| `map-squares` | 1/10 | 10% | 80% |
| `filter-evens` | 1/10 | 10% | 80% |
| `factorial-6` | 1/10 | 10% | 80% |
| `fibonacci-10` | 0/10 | 0% | 80% |

Every capability is below the release threshold. Failures remained explicit:
there were no observed false completions or duplicate executions in the final
Fibonacci report, and its lifecycle terminal rate was 100%. Common model
failures were missing Actions, invented Guile forms, malformed argument lists,
truncated output, and bounded LLM timeouts. GCAS preflight, Reflection, repair,
hidden-property verification, and terminal failure paths remained active.

## Resource envelope and segmentation

The diagnostic was assembled from complete per-capability cells after the
desktop task was interrupted. The first three cells came from:

```text
/tmp/gcas-qwen3.5-4b-readiness-v2-bounded512.jsonl
```

The complete factorial cell came from:

```text
/tmp/gcas-qwen3.5-4b-readiness-v2-bounded512-segment2.jsonl
```

Those four cells used `GAIA_LLM_MAX_OUTPUT_TOKENS=512` and a 120-second
per-call timeout. The complete Fibonacci cell and JSON report are:

```text
/tmp/gcas-qwen3.5-4b-readiness-v2-fibonacci-256.jsonl
/tmp/gcas-qwen3.5-4b-readiness-v2-fibonacci-256.json
```

Fibonacci used 256 output tokens and a 75-second timeout after 512-token calls
repeatedly occupied the GPU for the full timeout. A prior 512-token Fibonacci
segment had already completed two runs, both failures caused by timeouts.

Because the cells did not come from one uninterrupted invocation and Fibonacci
used a tighter output envelope, this is diagnostic evidence, not the canonical
single-run release artefact. It is nevertheless sufficient to reject readiness:
the four comparable 512-token cells already failed, and Fibonacci achieved no
success under either observed envelope.

## Operational finding

The LLM client now sends a positive `max_tokens` bound, configured with
`GAIA_LLM_MAX_OUTPUT_TOKENS`. A Guile-side timeout terminates the GCAS call, but
an in-flight LiteLLM/Ollama generation can continue briefly after client
interruption and delay the next request. Operators should unload the model and
wait for an empty `/api/ps` response before restarting a segmented run.

