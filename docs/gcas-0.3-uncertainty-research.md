# GCAS 0.3 — Uncertainty Research Synthesis and Architecture Decision

**Status:** Supporting, non-normative document

**Scope:** Uncertainty, metacognition, Global Workspace integration, and uncertainty-calculus selection

**Normative specification:** [`../gcas.md`](../gcas.md)

## 1. Purpose

This note records the research and design decisions behind the GCAS 0.3 uncertainty framework. It answers four questions that the
normative specification alone should not attempt to settle by assertion:

1. Why must a learning cognitive architecture represent uncertainty separately from correctness and verification?
2. How does probabilistic inference relate to Global Workspace Theory (GWT) and Global Neuronal Workspace (GNW)?
3. Does Zoubin Ghahramani's probabilistic-machine-learning programme directly ground a Global Workspace architecture?
4. Should GCAS require Bayesian inference exclusively, prefer it by default, or support several uncertainty calculi?

The resulting decision is **Bayesian reference semantics with typed pluralism**. GCAS-Core requires explicit, typed, auditable uncertainty,
but does not require every uncertainty quantity to be Bayesian. A separate Bayesian profile defines the stronger requirements for systems
that claim Bayesian belief-update and prediction semantics.

## 2. Correctness, Verification, Confidence, and Calibration

The terms describe different properties and must not be collapsed:

| Concept | Meaning | Typical evidence |
| :--- | :--- | :--- |
| **Correctness** | Whether a declared correctness target is actually satisfied. It is world- or contract-relative and may be unknown. | Later observation, accepted ground truth, proof plus grounded premises, or an executable oracle. |
| **Verification** | A bounded process and record that checks a named target with declared scope and coverage. | Test result, proof, independent observation, source check, or reproducible execution. |
| **Confidence** | A system's evidence-conditioned estimate of correctness, reliability, or appropriateness. | Posterior probability, calibrated score, interval, credal bound, or another declared uncertainty representation. |
| **Calibration** | A population-level relationship between earlier confidence assessments and later observed correctness. | Proper scores, calibration curves, coverage, sample counts, and a declared evaluation population. |

A claim may be correct with low confidence or incorrect with high confidence. A confidence of `0.97` is not an observation that the claim is
correct, and it does not create verification evidence. Conversely, verification of one bounded property does not establish correctness
outside the verifier's declared scope. Calibration evaluates a family of assessments; it cannot prove one unevaluated claim correct.

## 3. Global Workspace and Uncertainty Are Complementary

GWT/GNW and probabilistic inference answer different architectural questions:

* a Workspace theory describes selective access, integration, competition, and broadcast among specialised processors;
* an uncertainty calculus describes how uncertain representations are encoded, updated, compared, and propagated;
* decision theory describes how predictive uncertainty and consequences affect action, abstention, escalation, or information acquisition.

The strongest direct bridge located in the literature is Shea and Frith's *The Global Workspace Needs Metacognition*. They argue that
globally available representations should carry a metacognitive accompaniment such as confidence. Confidence supplies a common currency
for weighting, comparing, and integrating compressed representations from otherwise heterogeneous domain-specific systems. The paper
explicitly cites Ghahramani (2015) when noting the growing prominence of confidence-aware computation in artificial intelligence.

This finding strengthens the GCAS requirement beyond generic machine-learning hygiene: an uncertainty assessment is part of the contract by
which a representation can be used effectively after broadcast. It does not follow that Workspace admission proves correctness, that high
confidence must dominate competition, or that a complete local probability distribution must always be broadcast. A domain processor may
maintain a rich distribution while broadcasting a decision-relevant summary plus an assessment that identifies its semantics and lost detail.

Whyte's Predictive Global Neuronal Workspace (PGNW) provides a second bridge. The 2019 working hypothesis integrates GNW with predictive
processing; the later formal model with Smith casts neuronal dynamics as approximate Bayesian inference within an active-inference model.
These works show that probabilistic inference and Workspace-style broadcast can coexist in one computational account. They are neuroscience
models of conscious access, not evidence that a GCAS implementation is conscious and not proof that one Bayesian algorithm is mandatory.

## 4. What Ghahramani (2015) Does and Does Not Establish

Ghahramani's review treats probability theory as a principled language for learning from data and representing uncertainty about observations,
parameters, predictions, and model structure. Its Bayesian account supports several GCAS requirements:

* explicit priors, likelihoods, posteriors, and posterior predictive distributions;
* marginalisation over uncertain parameters and models instead of silent point-estimate substitution;
* approximate inference with computational limitations made visible;
* decision-making that uses predictive distributions rather than confidence alone;
* probabilistic programming, Bayesian optimisation, non-parametric models, and model discovery as implementation families rather than one
  fixed algorithm.

Ghahramani studied computer science and cognitive science and completed a doctorate in cognitive neuroscience. His research includes
probabilistic models of cognition and sensorimotor integration. The literature review for GCAS 0.3 did not locate evidence that he developed
or directly studied GWT/GNW. GCAS therefore uses Ghahramani to ground probabilistic learning, not Workspace theory.

The 2015 review strongly motivates Bayesian and probabilistic modelling but does not systematically compare Bayesian inference with credal
sets, Dempster-Shafer evidence theory, Subjective Logic, conformal prediction, possibility theory, or paraconsistent reasoning. GCAS's typed
pluralism is consequently an architectural decision informed by a broader literature; it must not be attributed to Ghahramani.

## 5. Candidate Uncertainty Representations

| Representation | Best fit in GCAS | Important limitation or assumption |
| :--- | :--- | :--- |
| **Bayesian probability** | Sequential belief update, prediction, model averaging, latent-state inference, expected utility. | Results are conditional on the prior, likelihood, model class, and inference quality; misspecification may produce precise but wrong posteriors. |
| **Imprecise probabilities / credal sets** | Severe ignorance, ambiguous priors, model-class uncertainty, and robust lower/upper expectations. | Decision and update rules must be declared; a set of distributions cannot be treated as one calibrated posterior. |
| **Subjective Logic / evidence masses** | Source reliability, explicit ignorance, conflicting or dependent testimony, trust networks. | Fusion operators rely on declared independence and base-rate assumptions; mappings to probabilities are not semantically free. |
| **Conformal prediction** | Model-agnostic prediction sets or intervals with finite-sample marginal coverage under declared exchangeability assumptions. | It does not supply a generative belief model or causal explanation; ordinary coverage guarantees can fail under distribution shift. |
| **Possibility or fuzzy measures** | Vagueness, graded category membership, and partially specified constraints. | Vagueness is not automatically epistemic probability; values must not be read as frequencies or posterior belief. |
| **Intervals and formal error bounds** | Numerical error, verified enclosures, runtime budgets, and bounded approximation. | Bounds need provenance and coverage; they may be conservative and need not encode belief. |
| **Truth-maintenance / paraconsistent state** | Logical contradiction, assumption tracking, and preservation of incompatible claims. | Contradiction is not a probability distribution; conflict must not be erased by scalar averaging. |

Several representations may coexist in one GCAS process because they answer different questions. They must not be silently fused for the
same target. A processor that converts between them must emit a versioned assessment that names the mapping, assumptions, information loss,
validation evidence, and destination semantics.

## 6. Architecture Decisions

### D1. Typed uncertainty is part of GCAS-Core

Every decision-relevant uncertain quantity must be representable by an auditable `UncertaintyAssessment`. Core conformance requires declared
semantics, scope, conditioning information, temporal validity, provenance, and update history. A verbal hedge or unlabelled scalar is
insufficient.

### D2. Bayesian inference is reference semantics, not the universal storage format

The normative text uses Bayesian inference as the reference model for probabilistic belief update and prediction. This makes prior-to-posterior
transitions, marginalisation, model uncertainty, and decision theory precise. Core conformance nevertheless permits another declared calculus.
The stronger `GCAS-Bayesian 0.3` profile requires a traceable Bayesian path for its covered domains.

### D3. Calculus selection is scoped to the target

An assessment must name its calculus. Different targets may use different calculi in the same process. More than one assessment may target the
same object only if their quantities, domains, assumptions, and relationship are explicit. No universal scalar confidence is defined.

### D4. Workspace broadcast carries metacognitive accompaniment

A decision-relevant Workspace candidate must either include or reference a current uncertainty assessment. Workspace scoring may consider
confidence, uncertainty, conflict, expected information gain, surprise, risk, urgency, and cost. Confidence alone must not determine admission:
low-confidence, high-risk, or anomalous content may deserve priority precisely because it requires deliberation or verification.

Broadcast changes availability, not epistemic authority. Receiving processors may update local beliefs only through declared evidence and
update rules; the number of processors receiving or repeating a claim is not corroboration.

### D5. Bayesian workflow includes model criticism

A Bayesian path is incomplete if it records only prior, likelihood, and posterior. Where material and feasible, it also requires prior
predictive checks, computational diagnostics, posterior predictive checks, sensitivity analysis, and a response to model misspecification.
Failed checks produce explicit uncertainty, revision, alternative-model, abstention, or escalation outcomes rather than a sharper posterior.

### D6. Calibration is paired with sharpness and shift handling

Forecast quality is not established by calibration alone. A system should maximise useful concentration or sharpness subject to calibration,
using proper scoring rules and coverage appropriate to the prediction type. Calibration claims are domain- and version-scoped. Distribution
shift invalidates transfer of those claims unless a documented shift-aware evaluation supports it.

## 7. Consequences for the Normative Specification

The GCAS 0.3 normative revision should:

1. replace the informal `UncertaintyAssessment` field list with a minimum schema and field-level requirements;
2. define uncertainty assessments as typed Cognitive Objects in `O`, with `U` as an indexed projection over those objects and their relations,
   rather than a second independent store of epistemic records;
3. specify calculus identifiers, quantity semantics, mappings, and combination prohibitions;
4. add prior-predictive, posterior-predictive, sensitivity, and misspecification transitions to the Bayesian workflow;
5. require Workspace candidates to reference decision-relevant uncertainty without making confidence an admission or truth threshold;
6. require calibration, sharpness, coverage, sample counts, and distribution-shift responses;
7. split calculus-neutral uncertainty requirements from the optional Bayesian conformance profile;
8. include a numeric end-to-end trace that preserves correctness, verification, confidence, and calibration as separate state.

## 8. Rejected Alternatives

* **Bayesian-only GCAS-Core:** rejected because it would conflate an architecture-level requirement to represent uncertainty with one family
  of representations and would handle severe ignorance, logical conflict, and formal error bounds awkwardly.
* **Calculus-neutral specification with no reference semantics:** rejected because interoperability claims would become too weak to test and
  belief-update language would remain ambiguous.
* **One scalar confidence attached to every Cognitive Object:** rejected because quantities with different targets, meanings, and calibration
  domains are not interchangeable.
* **Workspace priority monotonically increases with confidence:** rejected because risk, anomaly, conflict, and expected information gain can
  make uncertain content more important.
* **Broadcasting the complete local posterior:** rejected as a general requirement because Workspace representations are bounded and may be
  compressed; a traceable, decision-relevant summary is sufficient when information loss is declared.
* **Workspace broadcast as verification:** rejected because routing and epistemic support are independent transitions.

## 9. Selected References

1. Z. Ghahramani, “Probabilistic Machine Learning and Artificial Intelligence,” *Nature* 521, 2015, pp. 452–459.
   <https://doi.org/10.1038/nature14541>
2. N. Shea and C. D. Frith, “The Global Workspace Needs Metacognition,” *Trends in Cognitive Sciences* 23(7), 2019, pp. 560–571.
   <https://doi.org/10.1016/j.tics.2019.04.007>
3. C. J. Whyte, “Integrating the Global Neuronal Workspace into the Framework of Predictive Processing: Towards a Working Hypothesis,”
   *Consciousness and Cognition* 73, 2019, 102763. <https://doi.org/10.1016/j.concog.2019.102763>
4. C. J. Whyte and R. Smith, “The Predictive Global Neuronal Workspace: A Formal Active Inference Model of Visual Consciousness,”
   *Progress in Neurobiology* 199, 2021, 101918. <https://doi.org/10.1016/j.pneurobio.2020.101918>
5. A. Gelman et al., “Bayesian Workflow,” 2020. <https://arxiv.org/abs/2011.01808>
6. T. Gneiting and A. E. Raftery, “Strictly Proper Scoring Rules, Prediction, and Estimation,” *Journal of the Royal Statistical Society:
   Series B* 69(2), 2007, pp. 243–268. <https://doi.org/10.1111/j.1467-9868.2007.00587.x>
7. Y. Ovadia et al., “Can You Trust Your Model's Uncertainty? Evaluating Predictive Uncertainty under Dataset Shift,” *NeurIPS*, 2019.
   <https://papers.nips.cc/paper/9547-can-you-trust-your-models-uncertainty-evaluating-predictive-uncertainty-under-dataset-shift>
8. E. Hüllermeier, S. Destercke, and M. H. Shaker, “Quantification of Credal Uncertainty in Machine Learning,” *UAI*, 2022.
   <https://proceedings.mlr.press/v180/hullermeier22a.html>
9. A. Jøsang, *Subjective Logic: A Formalism for Reasoning Under Uncertainty*, Springer, 2016.
   <https://doi.org/10.1007/978-3-319-42337-1>
10. A. N. Angelopoulos and S. Bates, “A Gentle Introduction to Conformal Prediction and Distribution-Free Uncertainty Quantification,” 2021.
    <https://arxiv.org/abs/2107.07511>
