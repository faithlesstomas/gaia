# NCSI/J-lens integration plan

**Status:** accepted architecture; implementation not started

**Canonical checklist:** this document

**Participating projects:**

- **GCAS/GAIA** owns the neural-state semantics, epistemic invariants,
  Cognitive Objects, Workspace integration, Control policy, and evaluation.
- **RAI** owns the optional local neural sidecar: model and accelerator
  lifecycle, Transformers hooks, J-lens artifacts, inference, transport, and
  operational telemetry.

The project roadmaps record only their high-level epics and link here. Detailed
milestone status MUST be maintained in this file rather than copied between
the two repositories.

## 1. Objective

Add a model-independent Neural Cognitive State Interface (NCSI) to GAIA and a
J-lens implementation of that interface hosted by RAI. The first deliverable is
a read-only vertical slice that exposes compact, versioned neural observations
during generation and compares them with the current textual projection on the
same evaluation corpus. Activation steering is a later, separately gated
capability.

J-space is one possible NCSI adapter. It is not the logical Global Workspace,
does not replace Cognitive Objects, and is not required for GCAS-Core
conformance.

## 2. Architectural decision

The J-lens implementation lives in the RAI repository but runs as a separate,
optional process. Repository placement does not weaken the runtime boundary:
GAIA communicates with the sidecar only through the versioned NCSI protocol
and MUST NOT import RAI or Python implementation modules.

```text
typed GAIA Cognitive State
          |
          | generation request / optional intervention
          v
GAIA NCSI adapter
          |
          | local versioned protocol (Unix domain socket preferred)
          v
RAI neural sidecar
  Transformers model -> residual-stream hooks -> J-lens readout
          |
          | token events + compact NeuralStateObserved events
          v
GAIA JSPACE processor -> Observation CO proposals -> Workspace -> Control
```

The ordinary RAI daemon and the neural sidecar MAY share authentication, XDG
paths, typed contracts, and lifecycle utilities. They MUST remain separately
startable so that missing neural dependencies, model load failures, and
accelerator out-of-memory failures do not terminate the ordinary RAI runtime or
GAIA.

## 3. Ownership boundaries

### GCAS/GAIA owns

- the normative meaning and allowed effects of NCSI signals;
- the portable event schema and protocol version expected by GAIA;
- conversion of neural observations into explicit `observation` Cognitive
  Objects with neural provenance;
- Workspace proposal metadata and Cognitive Control policy;
- decisions to request, reject, limit, or terminate interventions;
- evidence, verification, process budgets, durable trace links, and fallback;
- adapter comparison and task-level acceptance gates.

### RAI owns

- loading, caching, unloading, and cancelling local model executions;
- accelerator admission, concurrency limits, memory accounting, and recovery;
- Hugging Face Transformers execution and residual-stream hooks;
- fitting, loading, validating, and versioning J-lens artifacts;
- sparse readout and, after a separate gate, steering/ablation/patching;
- compact streaming events, health/capability discovery, and sidecar telemetry;
- keeping raw activations and tensors inside the neural process.

### Neither side owns

- automatic promotion of a neural signal to `VERIFIED` or `ACCEPTED`;
- silent fallback that changes the advertised execution mode;
- an assumption that J-lens output is a faithful explanation of model
  computation without model- and task-specific causal validation.

## 4. Required invariants

1. A neural signal enters GAIA as an observation or proposal, never as a fact.
2. Every observation identifies the exact model revision, tokenizer, lens
   artifact, layer, position, request, and forward pass that produced it.
3. Lens artifacts are rejected when their manifest does not match the loaded
   model and tokenizer. Quantization or checkpoint changes require explicit
   compatibility validation.
4. Raw tensors remain in RAI. GAIA receives bounded concept activations and
   quality metadata only.
5. Read-only observation is implemented and evaluated before write-side
   intervention is enabled.
6. Every intervention is explicit, bounded, traceable, cancellable, and
   disabled by default.
7. Sidecar failure produces a typed failure and an observable fallback or
   terminal outcome; it never silently becomes a successful NCSI run.
8. NCSI does not bypass Action policy, sandbox execution, evidence collection,
   independent verification, or process budgets.
9. The current textual projection remains available as the baseline and
   fallback adapter.
10. Cancellation and terminal delivery retain the existing GCAS exactly-once
    lifecycle guarantees.

## 5. Initial protocol surface

The transport MAY be HTTP streaming, Server-Sent Events, or WebSocket. A Unix
domain socket is preferred for local deployment. The wire schema is transport
independent and starts with an explicit version such as `gcas.ncsi.v1`.

Minimum operations:

```text
GET  /api/v1/neural/capabilities
GET  /api/v1/neural/models
GET  /api/v1/neural/lenses
POST /api/v1/neural/generate
POST /api/v1/neural/requests/{request-id}/cancel
```

Minimum generation event union:

```text
GenerationStarted
TokenDelta
NeuralStateObserved
GenerationCompleted
GenerationFailed
```

`NeuralStateObserved` must contain at least:

```text
schema-version
request-id
forward-pass-id
model-id and model-revision
tokenizer-revision
lens-id and lens-revision
layer
position or token span
bounded concept list: token-id, display text, score
readout method and parameters
optional reconstruction error / calibration metadata
timestamp
```

The initial protocol does not expose arbitrary tensors, Python objects, model
hooks, filesystem paths, or an unrestricted steering vector.

## 6. Implementation layout

The recommended RAI layout is an optional vertical module, independent of the
legacy chat path:

```text
src/rai/neural/
  contracts.py
  service.py
  server.py
  artifacts.py
  engines/transformers.py
  inspectors/jlens.py
```

It should be installed through a dedicated optional dependency group and
started with a dedicated command, for example:

```text
rai neural serve --uds "$XDG_RUNTIME_DIR/rai/neural.sock"
```

The recommended GAIA layout is:

```text
src/gaia/ncsi.scm
src/gaia/rai-ncsi-adapter.scm
src/gaia/jspace-processor.scm
```

Exact names may change during implementation, but the transport adapter,
processor semantics, and ordinary text-generation adapter must remain
separable.

## 7. Artifact policy

Model weights and fitted lenses do not belong in either Git repository. RAI
stores them under its XDG data/cache hierarchy and versions a reproducible
manifest containing:

- model repository and immutable revision;
- tokenizer revision;
- architecture and selected layers;
- dtype and relevant quantization information;
- J-lens implementation revision and fitting parameters;
- calibration corpus identifier and license/provenance;
- artifact checksum and creation timestamp.

The first replication target should be a small Hugging Face decoder supported
by the reference J-lens implementation. The current Ollama/OpenAI-compatible
GAIA model path remains the baseline; it cannot be treated as the same neural
model unless exact checkpoint compatibility is established.

## 8. Evaluation and safety gates

All adapter comparisons run on the same versioned task corpus and record:

- terminal-response rate, hangs, and interruption latency;
- first-pass and repair success;
- verifier outcome and false-completion rate;
- model calls, executions, latency, token use, and accelerator memory;
- sidecar availability, schema failures, and fallback count;
- observation stability across repetitions and prompt-equivalent inputs;
- causal controls for any claimed behavioral effect.

Read-only NCSI may influence scheduling or trigger verification only after its
policy is explicit and tested. Steering requires matched controls such as a
text-only baseline, observation-only mode, no-op intervention, and appropriate
random or norm-matched interventions. A favorable example or introspective
report is not sufficient evidence of causal utility.

## 9. Milestones and canonical progress

### M0 — contract and conformance fixtures

- [x] Freeze the `gcas.ncsi.v1` event schema and error taxonomy.
- [x] Add transport-independent schema fixtures shared by both repositories.
- [x] Add GAIA tests proving that neural signals cannot directly create an
      accepted or verified Claim.
- [x] Define cancellation, timeout, incompatibility, and fallback outcomes.

**Acceptance gate:** both projects validate the same valid and invalid fixtures,
and GAIA deterministically preserves its epistemic and terminal-delivery
invariants without a real model.

### M1 — RAI Transformers engine

- [ ] Add the optional Transformers execution path without J-lens.
- [ ] Keep model ownership in a long-lived, separately startable process.
- [ ] Implement bounded concurrency, cancellation, unload, and typed failures.
- [ ] Record latency, token counts, model load time, and accelerator memory.

**Acceptance gate:** a pinned small model completes and cancels deterministic
test requests through the sidecar while the ordinary RAI runtime remains usable
when neural dependencies or an accelerator are absent.

### M2 — offline J-lens replication and artifacts

- [ ] Pin or vendor a reviewed revision of the reference J-lens code.
- [ ] Reproduce fit, save, load, and readout on the selected pilot model.
- [ ] Implement and validate the artifact manifest and mismatch rejection.
- [ ] Establish fitting and inference resource baselines.

**Acceptance gate:** a clean environment can recreate or obtain a checksummed
lens and reproduce the documented readout within declared tolerances.

### M3 — read-only neural sidecar

- [ ] Expose capability discovery and bounded generation streaming.
- [ ] Emit compact `NeuralStateObserved` events without raw tensors.
- [ ] Add authentication, request limits, health, and audit telemetry.
- [ ] Test disconnect, malformed artifact, OOM, timeout, and cancellation paths.

**Acceptance gate:** one generation produces a versioned token stream and linked
neural observations; every failure reaches the client as a typed terminal event.

### M4 — GAIA NCSI adapter and JSPACE processor

- [ ] Add the RAI NCSI transport adapter without changing execution or verifier
      semantics.
- [ ] Represent neural outputs as observation COs with durable provenance.
- [ ] Submit bounded Workspace proposals with explicit uncertainty.
- [ ] Implement observable fallback to the current textual projection.

**Acceptance gate:** mocked and live sidecars drive the production Cognitive Bus
without bypassing Workspace, Control, Action, Evidence, or Goal Verification.

### M5 — comparative evaluation and readiness decision

- [ ] Run text-only and text-plus-read-only-NCSI modes on the same corpus.
- [ ] Measure stability, calibration, overhead, failure modes, and task utility.
- [ ] Document per-model and per-task thresholds and unsupported claims.
- [ ] Decide whether read-only NCSI is ready for an opt-in experimental profile.

**Acceptance gate:** the evaluation report supports an explicit ship, revise, or
reject decision and reports all hangs, false completions, fallbacks, and costs.

### M6 — controlled write-side intervention

- [ ] Define allowlisted steering, ablation, and patching request types.
- [ ] Add Control policy, strength/layer/position budgets, audit, and kill switch.
- [ ] Add matched causal controls and regression tests.
- [ ] Demonstrate rollback/fallback when intervention is unavailable or unsafe.

**Acceptance gate:** intervention has reproducible causal benefit on a declared
task class without weakening lifecycle, policy, or verification guarantees.

### M7 — downstream neuro-symbolic applications

- [ ] Evaluate J-space-to-STI mapping after AtomSpace and STI/LTI exist.
- [ ] Evaluate typed DSL mismatch probes after `$gscm` has a symbolic oracle.
- [ ] Evaluate prover-guidance and cognitive-state serialization independently.

**Acceptance gate:** each application has its own ablation against simpler
textual or symbolic controls and remains optional to GCAS-Core.

## 10. Work tracking

- This file is the only canonical milestone checklist.
- The GAIA and RAI roadmaps each contain one high-level epic linking here.
- Atomic implementation work belongs in the relevant repository's issue
  tracker and should link back to a milestone in this document.
- Cross-repository changes should reference the same schema version and fixture
  revision.
- Milestone status changes require current code or documentation, relevant
  tests, an explicit failure mode, and updated acceptance evidence.

## 11. References

- GCAS NCSI requirements: `gcas.md`, sections 7.3 and 7.4.
- GAIA prompt projection: `docs/gcas-prompt-projection.md`.
- J-space paper: <https://transformer-circuits.pub/2026/workspace/index.html>
- Reference J-lens implementation:
  <https://github.com/anthropics/jacobian-lens>
- RAI architecture and roadmap:
  <https://gitlab.com/tk-lab1/ai/rai>
