# SmolLM2 J-lens M5 evaluation

**Decision:** `SHIP_EXPERIMENTAL` for an opt-in, read-only NCSI profile.

This is a technical integration decision, not evidence that J-lens readouts are
epistemic truth, complete model thoughts, or causally useful for task solving.

## Configuration

- model: `HuggingFaceTB/SmolLM2-135M`
- immutable model revision: `93efa2f097d58c2a74874c7e644dbc9b0cee75a2`
- lens requested as: `smollm2-jlens-v1`
- selected artifact checksum: `5f444d3fd89aeda442dc449634034bc0d1cbf792b5d981f807ab0b37378ffd29`
- GAIA implementation revision: `52aa814546485062d7b8cfb73023ddac07ec13ff`
- RAI implementation revision: `29baaa53b262bdd280ae9549696751f37c2c3f36`
- observed layer: 12
- tasks: capital of France, simple addition, freezing point of water
- modes: `TEXT_ONLY`, `OBSERVATION_ONLY`, `NCSI_POLICY`
- repetitions: 2 per task and mode (18 runs total)
- maximum new tokens: 12

The local lens directory named `smollm2-jlens-v2` still declares artifact ID
`smollm2-jlens-v1`. RAI now rejects such duplicate IDs when both directories are
visible. This run used a temporary registry exposing only that selected,
checksummed artifact; the user-owned artifacts were not modified.

The stable configuration, aggregate metrics, and readiness inputs are also
committed as
[`ncsi-smollm2-m5-summary.json`](ncsi-smollm2-m5-summary.json). The lens payload
itself is not committed. Recreating or independently obtaining that payload in
a clean environment remains an open M2 acceptance item rather than an implied
property of this M5 integration run.

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

The run report was produced by `scripts/run-ncsi-evaluation.scm`. The raw file
is intentionally not committed because it contains run-specific request IDs
and timings; the stable aggregate is committed separately. After starting the
pinned RAI sidecar, reproduce the run from the GAIA checkout with:

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

The readiness decision is reproducible from the report fields. Exact latency
is hardware-dependent, and concept-set equality is expected only for the same
model, tokenizer, lens payload, generation parameters, and deterministic
execution settings.
