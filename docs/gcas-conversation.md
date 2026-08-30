# GCAS conversation in the GAIA MVP

## User-visible contract

Plain input in the Rust CLI and Emacs client is an ordinary assistant turn. It
is no longer an alias for executable `solve` and is not sent as an accumulating
provider transcript. The public paths are:

| Input | Meaning |
|---|---|
| plain text or `/chat <message>` | bounded, memory-backed GCAS conversation |
| `/solve <goal>` | governed Action execution for a registered capability with an independent private verifier |
| `/ask <message>` | explicitly legacy one-shot LLM request outside a GCAS process |
| `/investigate <goal>` | explicitly legacy recursive LLM–REPL investigation |

The default client session is selected from `GAIA_SESSION_ID`, then the
project-local `.last_session`, then a fresh generated identifier. The server
persists the UI/audit transcript as `sessions/<id>.json` and the authoritative
cognitive records as `sessions/<id>.gcas-memory.scm` and
`sessions/<id>.gcas-state.scm`. Session identifiers are validated before they
are used as storage names. `/clear` creates an explicit fresh memory boundary.

## One conversational turn

One turn creates an independent bounded Cognitive Process:

```text
user utterance
  -> Goal + USER Observation
  -> Memory retrieval
  -> bounded non-transcript context Observation
  -> Workspace selection and broadcast
  -> LLM HYPOTHESIS/UNVERIFIED
  -> delivery Evidence
  -> DELIVERY_ONLY verified Claim
  -> exactly one terminal Answer
```

The LLM adapter always receives an empty `history` list. The prompt contains a
bounded recent conversational episode plus bounded relevant semantic,
procedural, testimony, episodic, and metacognitive records. The current user
utterance is carried by the active Goal and is excluded from duplicate memory
projection. The default reconstructed context is capped at 6000 characters.

User profile-like assertions such as “Mam na imię Tomasz” are retained as
`USER_TESTIMONY` Observations. This verifies only that the user supplied the
statement; it does not make the proposition a world fact. Questions containing
the same words, such as “Jak mam na imię?”, remain ordinary episodic turns.

Assistant prose is stored as an LLM-origin `hypothesis` with
`HYPOTHESIS`/`UNVERIFIED` status. The Goal Verifier separately verifies only
that a non-empty bounded response was delivered. Its accepted Claim carries
`verification-scope = DELIVERY_ONLY`; it never promotes factual statements in
the response.

## Why the server may look similar

The wire protocol still ends with a familiar `(final "...")`, so a successful
turn intentionally looks like chat. The architectural difference is visible in
the trace and durable state rather than in extra prose added to every answer:

- `/cognitive-events` shows `ConversationTurnReceived`, `MemoryRetrieved`,
  Workspace rounds/broadcasts, `HypothesisProposed`,
  `ResponseDeliveryVerified`, `GoalVerificationCompleted`, `GoalVerified`, and
  `GoalCompleted`;
- `/cognitive-state` shows typed turns, provenance, epistemic state, relations,
  active Control budgets, Workspace state, and durable Memory;
- `gaia-server.log` records the same ordered semantic events with the session
  identifier;
- restarting the client or server with the same logical session reconstructs
  the next prompt from durable CO Memory without replaying the JSON transcript.

## Verification

`make gcas-conformance` includes model-free coverage for two-turn recall after
restoration, empty provider history, bounded prompt growth, exactly-once
completion, interruption/late-callback behavior, and the non-promotion of
assistant content.

The opt-in live gate uses one explicitly approved model and two LLM calls:

```bash
GAIA_EVAL_MODELS='<litellm-model-name>' \
GAIA_EVAL_MODEL_PARAMETERS_B=4 \
GAIA_EVAL_RESOURCE_APPROVED=1 \
GAIA_EVAL_VERBOSE=2 \
GAIA_CONVERSATION_EVAL_OUTPUT=/tmp/gcas-conversation.json \
make gcas-live-conversation-eval
```

This target is local-only and fails closed whenever the `CI` environment
variable is present. It is not part of any GitLab pipeline, `make check`, or
`make gcas-conformance`; those commands exercise only its model-free contract.

It establishes a nonce in turn one, constructs a fresh session object, asks for
the nonce in turn two, and checks recall, bounded non-transcript projection,
empty provider history, assistant epistemic status, delivery-only Claims, and
terminal outcomes. `GAIA_LLM_TIMEOUT_SECONDS` bounds each synchronous LiteLLM
call (300 seconds by default). The ordinary five-capability readiness matrix is
still run separately with `make gcas-live-eval`.

The live gate demonstrates coherent bounded recall for one declared model and
runtime configuration. It does not establish open-ended factual accuracy,
general long-term memory quality, or broad benchmark competence.

The recorded MVP run passed on `qwen3.5-4b` under a single-model 4.7B envelope;
see [the evaluation report](evaluations/gcas-conversation-qwen3.5-4b-mvp.md).
