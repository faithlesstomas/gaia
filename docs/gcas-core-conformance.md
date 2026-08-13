# GCAS-Core Conformance Audit

This is the implementation-level conformance record for GAIA against the eight
minimum requirements in [GCAS §11.2](../gcas.md#112-minimal-conformance-requirements-gcas-core).
It concerns **GCAS-Core**, not every optional or future GCAS capability.

| GCAS-Core requirement | GAIA implementation | Acceptance evidence |
|---|---|---|
| Explicit COs, 3-axis metadata, provenance | `gaia com` defines immutable COs with epistemic status, verification status, confidence, temporal validity, provenance and relations. | CO validation tests and the executable showcase. |
| Hypotheses distinct from beliefs | LLM output is created only as `HYPOTHESIS`/`UNVERIFIED`; the deliberative processor alone can produce verified accepted claims. | `test-deliberative-processor.scm`; production `solve` returns `INCONCLUSIVE` without goal-specific proof. |
| Bounded workspace | `gaia workspace`, `gaia cognitive-session`, and `gaia cognitive-control` implement candidate submission, deterministic selective admission, broadcast after admission, and capacity release at termination. | `test-cognitive-session.scm`; `test-gcas-showcase.scm`. |
| Generative and deliberative processors | The LLM adapter is the Generative Processor. `gaia deliberative-processor` converts execution observations into Evidence and verified Claim or Conflict through an injected verifier. | `test-deliberative-processor.scm`; `test-actors.scm`. |
| Memory separate from transcript history | `gaia cognitive-memory` persists structured COs, retrieves them by current goal, and reconstructs the solver context. `solve` sends that projection with empty chat history. | `test-actors.scm`; `docs/gcas-core-cycle.md`. |
| Recurrent cycle and loop monitoring | The event-driven cycle repeatedly admits COs across question, goal, hypothesis, action, evidence, claim/conflict, reflection and terminal outcome. Control tracks transitions, observable progress, stalled transitions, failures, and user interruption. | `test-cognitive-session.scm`; `test-gcas-showcase.scm`. |
| Separate auditable execution | Only an admitted `Action` CO reaches the sandbox. A `Result` or `Failure` links back to that Action and receives a reproducibility observation. | `test-cognitive-session.scm`; `test-actors.scm`. |
| Uncertainty, time, failure | COs explicitly model confidence and validity intervals. `FAILED`, `INCONCLUSIVE`, `INSUFFICIENT_INFORMATION`, conflict, and user interruption are recorded terminal states. | `test-gcas-showcase.scm`; `test-cognitive-session.scm`. |

## Architectural boundary

The server remains the owner of session-local Cognitive State, Workspace, Bus,
Control, Memory, processors, and sandbox. Unix-socket IPC is only a transport
boundary. The Rust CLI and Emacs client are thin protocol clients: normal input
uses `solve`, `/investigate` explicitly selects the legacy recursive LLM–REPL
processor, and `/cognitive-events` exposes the audit trace. This topology is
compatible with GCAS because clients neither decide admission nor mutate belief.

## Deliberate limits after Core

GCAS-Core does not imply that every `solve` request establishes a world fact.
The current production verifier establishes only the bounded fact that an
approved Action produced the observed sandbox output; the original question
remains `INCONCLUSIVE` until an independent goal-specific verifier is added.
Cryptographic environment manifests, adaptive attention, semantic/procedural
memory consolidation, distributed buses, and NCSI/J-space are post-Core work.
