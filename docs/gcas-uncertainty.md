# GCAS 0.3 uncertainty implementation

GAIA stores uncertainty as immutable, versioned Cognitive Objects. The
authoritative records are `uncertainty-assessment`, `calculus-declaration`,
`correctness-observed`, and `calibration-record`; projection `U` is rebuilt
from Cognitive State and graph relations and is never a second database.

The machine-valid assessment contract includes target and quantity, calculus
and version, representation and outcome space, semantics and units, typed
uncertainty sources, conditioning evidence, assumptions, lineage and
dependence, method and diagnostics, prior versions, calibration scope,
producer, and temporal validity. Invalid or incomplete records fail closed.
Invalidation follows `conditioned-on` and `updates` dependencies, while
supersession retains both versions and their original numeric values.

The first Bayesian profile is deliberately narrow: exact Beta–Bernoulli
inference for a verifier-backed Bernoulli failure-rate target. Its deterministic
gate reproduces the GCAS worked trace: `Beta(1,9)`, `Beta(2,28)`, and
`Beta(2,58)`, including prior/posterior predictive probabilities, sensitivity
against `Beta(1,1)`, immutable correctness feedback, and Brier/log-loss
calibration.

Control treats priority, relevance, urgency, risk, conflict, out-of-domain
state, expected information gain, and cost as inspectable decision features.
Workspace admission never changes correctness, verification, or assessment
values. Goal policies provide their own acceptance threshold and may instead
abstain, escalate, or acquire evidence. Cross-calculus values cannot be
combined without an explicit mapping.

Run the profile gate with:

```sh
GUILE_AUTO_COMPILE=0 guile -L src tests/test-uncertainty.scm
```

It is also part of `make gcas-conformance`.
