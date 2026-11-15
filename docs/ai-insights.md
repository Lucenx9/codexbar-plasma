# AI Insights

This reference owns the optional assistant's data, request, credential, and
lifecycle contracts. The [usage guide](usage.md#ai-insights) describes setup and
controls. AI Insights is disabled by default and explains normalized widget data.

## Presentation

The assistant appears in Usage & Spend, or the provider view of a fixed-provider
widget. Navigation and disclosure never generate an answer. Manual requests use
one of four fixed intents: `summary`, `changes`, `headroom`, or `investigate`.
Automatic requests use `summary`.

Its scope is all current providers and two complete historical weeks,
independent of selected chart days, models, or projects. Answers can explain
provided facts and CLI forecasts; they cannot establish causality, invent savings,
or treat provider quotas as interchangeable. A saved answer retains its question,
generation time, service, model, and evidence identifier. Current figures cannot
be cited as evidence for an older answer. Failures preserve that answer.
Version-1 caches without a question default to `summary`.

## Boundary decision

Provider fetching, authentication, and CodexBar configuration remain in the
upstream CLI. AI Insights consumes already normalized usage and cost snapshots;
it never accesses CodexBar configuration or credentials. Ollama, OpenRouter, and
OpenAI are text-generation destinations in this role, with separate keys from
any CodexBar monitoring credentials.

The feature has no macOS equivalent or missing CLI generation contract.
A packaged Python helper performs bounded HTTP requests, as the widget's release
and managed-CLI helpers do for their own operations.

## Architecture

| Responsibility | Owner |
| --- | --- |
| Allowlisted snapshot and deterministic signals | `contents/ui/AiInsightsSnapshot.js` |
| Language, context, cache, and schedule | `contents/ui/AiInsights.js` |
| Helper commands, private-input paths, reply validation | `contents/ui/AiInsightsProtocol.js` |
| Process, nonce, deadline, stale replies, timer | `contents/ui/controllers/AiInsightsController.qml` |
| Persistence and localized messages | `main.qml`, `components/AiInsightsMessages.qml` |
| Guided questions and saved answers | `components/AnalysisAssistant.qml` |
| Secret Service, HTTP, input and response validation | `scripts/lib/ai_insights.py`, `scripts/lib/ai_insights_input.py` |
| Settings, key prompt, model discovery | `configAiInsights.qml` |

The controller and settings page call `AiInsightsProtocol`; cache and schedule
policy stay independent of transport. Snapshot inputs come from existing
`ProviderSnapshot.js`, `CostResponse.mjs`, and normalized pace fields.
`UsageAnalysis.js` and `ChartLines.mjs` own chart selection separately.

When `aiInsightsEnabled` is false, no snapshot, timer, or generation process is
active and saved answers are hidden. Setup guidance can still open without
building a snapshot. Model and wallet lookups run from settings only after
enablement or an explicit action.

## Language

Requests use the catalog language resolved by `i18n()`, not the numeric locale,
`Qt.uiLanguage`, provider, or model. Each catalog translates a BCP 47 marker
(`msgctxt` "BCP 47 language tag of this translation...", `msgid` "en") to its
tag: `it`, `de`, `fr`, `es`, or `pt-BR`. Missing catalogs fall back to English.

This distinction matters under `LANG=C.UTF-8 LANGUAGE=it`: gettext displays
English while `Qt.locale().name` reports `it_IT`. The `ai-insights-mismatch`
scenario exercises that case.

`AiInsights.languageTag` bounds and normalizes the marker. `--language` passes
it to the helper's fixed instructions. Language participates in cache context;
an answer in another language is not current. A language change alone does not
make generation due.

## Snapshot contract

`AiInsightsSnapshot.build(providers, nowMs, warningPercent)` builds a new
allowlisted object, never copying source records. Guided requests add a validated
`question` enum through `forQuestion`, deriving a separate identifier for
non-summary intents. The helper maps that enum to fixed instructions and accepts
no free-text prompt.

```json
{
  "version": 1,
  "providers": [{
    "id": "codex",
    "quotas": [{"window": "primary", "usedPercent": 72, "windowHours": 5,
                "resetsInHours": 2, "forecast": "runsOutBeforeReset",
                "runsOutInHours": 1, "expectedUsedPercentNow": 40}],
    "spend": {"currency": "USD", "last7Days": 21, "previous7Days": 14,
              "changePercent": 50, "estimated": true},
    "tokens": {"last7Days": 14000, "previous7Days": 7000, "changePercent": 100},
    "incident": "major"
  }],
  "signals": [{"kind": "quotaRunsOutBeforeReset", "provider": "codex",
               "window": "primary", "runsOutInHours": 1, "resetsInHours": 2}]
}
```

- Provider IDs match `^[a-z0-9][a-z0-9._-]{0,63}$`. The builder never reads
  account identity, organizations, login methods, CLI prose, titles, extra-window
  labels, detail rows, models, projects, paths, sessions, or errors.
- Only current measured providers are included, at most eight, with at most
  four authoritative quota rows each. Estimated and unknown-confidence usage
  cannot establish headroom. Legacy confidence behavior is retained. Stale,
  empty, or unavailable providers are excluded; no current provider means no
  request. Forecasts come only from normalized CLI pace, never extrapolation.
- Spend and token comparisons require already loaded history covering all
  fourteen complete days before today and reaching today, with finite amounts,
  established coverage, and no missing, unknown, partial, or duplicate dates in
  that span or today. Duplicates outside it do not invalidate comparisons.
  Generating an insight never starts a cost scan.
- Currencies remain per provider and are never summed across providers.
  Approximate or estimated sources, including an estimated share, set
  `estimated`. Unpriced, unmetered, or incomplete-request days set `incomplete`.
- `resetsInHours` requires a valid ISO timestamp with an explicit timezone.
  Invalid or ambiguous resets omit that time without discarding the quota.
- Signals cover exhausted quota, CLI forecast exhaustion before reset, the
  configured warning threshold, period changes of at least 25%, and known
  incidents. Fractional percentages prevent rounding across thresholds.
  Increases above 300% use `changeMultiple`, never both ratio and percentage.
- Serialized snapshots are ASCII, at most 16 KiB, and identified by an FNV-1a
  hash. Automatic generation skips evidence identical to the cached answer.

Privacy mode leaves this snapshot unchanged: it contains none of the identity
or prose that privacy hides.

## Request contract

The helper sends one non-streaming request containing fixed English instructions
and the snapshot JSON. A final reminder sets the output language. Instructions
require provided facts, the selected language's decimal separator, no invented
forecasts or cross-currency arithmetic, and no equivalence between provider
percentages. Data is never interpreted as instructions. A `changeMultiple` or
`changePercent` must be reproduced without conversion.

The requested summary has one or two sentences, at most 30 words. Highlights
have at most 12 words each and add facts absent from the summary. The response
JSON Schema also appears in the instructions.

| Provider | Endpoint | Request settings |
| --- | --- | --- |
| Ollama | `POST {endpoint}/api/chat` | Schema in `format`, `stream: false`, `think: false`, `keep_alive: 0`, `temperature: 0`, `num_predict: 4000`, prompt-sized `num_ctx`, no credentials |
| OpenRouter | `POST https://openrouter.ai/api/v1/chat/completions` | Strict `json_schema`, `max_tokens: 4000`, `provider.require_parameters`, `provider.data_collection: "deny"`, optional `provider.zdr`, app attribution headers |
| OpenAI | `POST https://api.openai.com/v1/chat/completions` | Strict `json_schema`, `max_completion_tokens: 4000`, `store: false` |

OpenRouter checks public `/models/{id}/endpoints` without a key. If an endpoint
advertises both `reasoning` and `structured_outputs`, generation adds
`reasoning: {"effort": "none"}` to avoid spending the output budget on hidden
reasoning. A failed lookup omits it. A `model`, `routing`, or parameter-related
`request` failure retries once without that setting if at least 30 seconds
remain. No model fallbacks are sent; `openrouter/*` aliases are rejected to
preserve the selected model's privacy terms.

Ollama models that require thinking can ignore `think: false` and exhaust the
output bound. `num_ctx` covers the whole prompt at two characters per token plus
the output budget, preventing a long prompt from losing its opening instructions.

Discovery returns at most 500 unique IDs: installed Ollama models, OpenRouter
structured-output models excluding Batch variants, and OpenAI Chat Completions
families supporting `json_schema`. The helper's model filters exclude
Responses-only and older incompatible families. No cloud model or price is
chosen automatically. Model-list replies allow 256 Ki characters for bounded
IDs, labels, and JSON escaping; generation and wallet replies allow 64 Ki.
An untagged Ollama name matches installed `:latest`; explicit tags and registry
ports match exactly. Only a colon after the final slash denotes a tag, following
the pinned [Ollama name parser tests](https://github.com/ollama/ollama/blob/675150d6ad2747df1e218ef59de9194bc4a7e538/types/model/name_test.go#L73).

Answers have shape `{"summary": string, "highlights": [string]}`. The helper
accepts fenced JSON, bounds summaries to 600 characters and three highlights
to 160 characters each, strips controls and Markdown emphasis, and rejects
malformed types, empty or oversized content, refusals, and truncated output
(`finish_reason` or `done_reason` `length`). QML validates again and renders
plain text. Snapshot, HTTP, error, and model-content JSON nesting is bounded to
32 levels, excluding brackets inside strings.

Failures become bounded reasons: `missing_key`, `secret_unavailable`, `auth`
(401), `credits` (402 or OpenAI `insufficient_quota`), `forbidden` (403), `model`
(404 or invalid/router model), `request` (400/422), `rate_limited` (429),
`timeout`, `network`, `routing` (OpenRouter 503), `unavailable`, `refused`,
`truncated`, `format`, `invalid_input`, and `endpoint`. `Retry-After` accepts
seconds or an HTTP date, bounded to 24 hours. OpenRouter `200 OK` error envelopes
use the same numeric-code mapping and header handling; a choice ending in
`error` is unavailable. Remote error bodies never reach the UI.

## Credentials and destinations

Snapshots never enter process arguments. A `prepare` action creates a random
`0700` request directory and `0600` `payload.ini` under
`codexbar-plasma-ai-<uid>`. Its base is a private, existing, absolute,
non-symlink `XDG_RUNTIME_DIR` owned by the user, otherwise the OS temp directory.
Lexical normalization removes empty and dot segments. An unsafe occupied root
fails closed without repair or deletion, even if that prevents generation.

The controller captures context before preparation and accepts only the expected
absolute `<root>/<request>/payload.ini` path without empty, `.` or `..` segments.
It writes an ASCII snapshot as hex through `QtCore.Settings`, synchronizes it,
and destroys the Settings object. Commands carry only `--request <random-id>`.
`ai_insights_input.py` validates ownership, permissions, regular-file type,
link count, age, size, INI, and hex before decoding UTF-8. It consumes and deletes
the file before wallet access or HTTP. Cancellation uses idempotent `discard`;
later preparation prunes private crash leftovers older than five minutes.
The old `--snapshot` argument is rejected. API keys never enter this file or QML.

Keys use Secret Service, normally KWallet on Plasma 6, through `secret-tool`
attributes `application app.codexbar.plasma`, `service ai-insights`, and
`provider <id>`. The helper prompts with `kdialog --password`, stores via stdin,
and performs lookups internally. Keys never enter QML, process arguments,
environment, URLs, logs, caches, or output. There is no plaintext fallback or
custom encryption; unavailable wallets produce `secret_unavailable`.

Cloud destinations are fixed HTTPS URLs with certificate verification.
Authorization uses an unredirected header and all redirects are refused.
Ollama permits HTTPS or loopback-only HTTP (`localhost`, `127.0.0.0/8`, `::1`),
rejecting user info, paths, queries, and fragments. Remote destinations are
identified in settings. Loopback ignores HTTP proxy variables.

**Test connection** lists models and, for OpenRouter, checks the key without
paid inference. It confirms the configured model exists; OpenRouter listing
proves structured-output support, not ZDR routing. Editing an endpoint retires
its test and clears the verdict. Editing a model clears the verdict but keeps
the list. Cloud tests update key status from the wallet. Disabling retires
settings helpers, clears status, ignores late replies, and blocks new requests.
A wallet-status deadline reports unavailable and rejects later status replies.

## Scheduling and lifecycle

Generation is manual after enablement, with optional 6-hour, 12-hour, or daily
intervals. Usage refreshes, popup opening, and language changes cannot trigger
a request. Automatic timing uses both the last success and the persisted last
attempt, so failed or possibly billed requests wait a full interval across
restarts. Identical evidence and context stay idle even after that interval,
including saved guided answers.

Only one request runs, with a fresh nonce. HTTP waits at most 150 seconds, GNU
`timeout` bounds the shell to 180 seconds, and QML waits 185 seconds from the
start of generation, independent of preparation time. Wallet unlock, model
lookup, and retry share a 170-second generation budget. No HTTP request starts
with less than 30 seconds left. Output allows 4000 tokens including reasoning.
Each HTTP deadline covers connection, headers, and bodies, preventing trickled
bytes from extending it. Once error headers arrive, a slow optional body cannot
erase the status or `Retry-After`. Shell termination is classified as timeout,
including Qt's SIGKILL result for the timeout owner.

Context changes (provider, model, endpoint, privacy routing, language), disabling,
and destruction retire requests and reject late replies. Commands `exec` GNU
`timeout`. The Linux helper's parent-death signal kills that timeout-owned
process group, including dialogs and wallet children, when Plasma kills its
owner. The guard fails closed unless its parent is `timeout`, owns the group,
and supports the required API. A submitted remote request can still complete
or be billed. Other-context answers are never current.

Generation, model-list, and wallet success require normal process exit with
numeric or integer-string zero. Missing, null, boolean, blank, or array exit
fields cannot confirm success, even with success JSON. Structured failures
remain available and never change usage data or replace a saved answer.

Every failure delays automatic generation by the interval, or 24 hours in
manual mode. Rate limits also enforce `Retry-After` from five minutes through
24 hours. Explicit retries obey only that rate-limit deadline. Persisted
`aiInsightsRateLimit` is context-specific, survives restarts, rejects deadlines
beyond 24 hours, and clears on success. Answers older than the interval, or
followed by a failed attempt, remain visible as out of date.

## Verification

Run `make check`; use [testing](testing.md) to select narrower checks. Pure
entry points are `tst_ai_insights.qml`, `tst_ai_insights_snapshot.qml`, and
`tst_ai_insights_view.qml`. Process and HTTP fixtures are `test_ai_insights.py`,
`test_ai_insights_input.py`, `test_ai_insights_controller.py`, and
`test_ai_insights_settings.py` under `tests/`.

Synthetic `ai-insights*` and `settings-ai-insights*` smoke scenarios exercise
production UI wiring, language, and lifecycle behavior. Tests contact no real
AI service, wallet, or credential. Executed results belong in the PR.
