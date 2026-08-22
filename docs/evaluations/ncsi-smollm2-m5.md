# SmolLM2 J-lens M5 evaluation

**Decision:** `SHIP_EXPERIMENTAL` for an opt-in, read-only NCSI profile.

This is a technical integration decision, not evidence that J-lens readouts are
epistemic truth, complete model thoughts, or causally useful for task solving.

## Configuration

- model: `HuggingFaceTB/SmolLM2-135M`
- immutable model revision: `93efa2f097d58c2a74874c7e644dbc9b0cee75a2`
- lens requested as: `smollm2-jlens-v1`
- observed layer: 12
- tasks: capital of France, simple addition, freezing point of water
- modes: `TEXT_ONLY`, `OBSERVATION_ONLY`, `NCSI_POLICY`
- repetitions: 2 per task and mode (18 runs total)
- maximum new tokens: 12

The local lens directory named `smollm2-jlens-v2` still declares artifact ID
`smollm2-jlens-v1`. RAI now rejects such duplicate IDs when both directories are
visible. This run used a temporary registry exposing only that selected,
checksummed artifact; the user-owned artifacts were not modified.

## Results

| Mode | Terminal | Task success | Fallback | Mean latency | Observations | Workspace proposals | Repeat stability |
|---|---:|---:|---:|---:|---:|---:|---:|
| `TEXT_ONLY` | 100% | 66.7% | 0% | 0.350 s | 0 | 0 | 1.00 |
| `OBSERVATION_ONLY` | 100% | 66.7% | 0% | 0.532 s | 12/run | 0 | 1.00 |
| `NCSI_POLICY` | 100% | 66.7% | 0% | 0.478 s | 12/run | 12/run | 1.00 |

The generated text matched exactly between `TEXT_ONLY` and
`OBSERVATION_ONLY`. Read-only observation therefore did not perturb the
deterministic output in this run. The policy mode submitted bounded observation
proposals to Workspace without promoting them to accepted or verified claims.

The capital task failed the deliberately simple substring criterion because the
small model generated a continuation without `Paris` in the 12-token budget.
This failure was identical in all modes, so it is model/task behavior rather
than an NCSI transport regression.

## Interpretation

Concept sets were perfectly repeatable under deterministic generation, but
included both task-relevant readouts (for example `countries`, `city`,
`arithmetic`, `temperature`, `Celsius`) and conspicuous unrelated or
sub-token readouts. Stability is therefore not semantic correctness or
calibrated confidence. The present result justifies exposing the feature as an
experimental observation channel. It does not yet justify treating J-space as
the Global Workspace or using readouts as facts.

The machine-readable report was produced by `scripts/run-ncsi-evaluation.scm`.
It is intentionally not committed because it contains run-specific request IDs
and timings; the command can reproduce the same report against a pinned local
sidecar.
