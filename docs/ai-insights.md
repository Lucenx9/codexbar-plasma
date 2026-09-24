# AI Insights

AI Insights is an optional, disabled-by-default Overview card that asks a
language model to explain a small, validated snapshot of the usage the widget
already shows. This document records its boundary decision, data contract,
request contract, and verification. The [usage guide](usage.md#ai-insights)
describes setup and behavior for users.

## Boundary decision

AGENTS.md assigns provider logic, authentication, config parsing, and quota
fetching for CodexBar providers to the upstream `codexbar` CLI. AI Insights
does none of that: it consumes quotas, pace forecasts, and cost history that the
widget has already normalized from supported CLI commands, and it never reads
or writes CodexBar configuration or provider credentials. The language-model
services it calls (Ollama, OpenRouter, OpenAI) are not CodexBar usage providers
in this role, even where CodexBar can also monitor them. Their API keys are
separate from any key stored in the CodexBar CLI configuration.

The official macOS app has no equivalent feature and the CLI has no text
generation command, so no CLI contract is missing and no TODO entry exists.
The transport follows the widget-owned helper pattern already used by the
release checker and managed CLI: a packaged Python helper performs bounded
network requests and returns semantic JSON records.

## Architecture

| Layer | Owner |
| --- | --- |
| Normalized provider snapshots | Existing `ProviderSnapshot.js`, `CostResponse.js`, pace fields |
| Allowlisted snapshot and deterministic signals | `contents/ui/AiInsightsSnapshot.js` |
| Language, context, cache, schedule, command, and reply validation | `contents/ui/AiInsights.js` |
| Process, nonce, deadline, stale replies, interval timer | `contents/ui/controllers/AiInsightsController.qml` |
| Persistence and localized error text | `main.qml` and `components/AiInsightsMessages.qml` |
| Card presentation | `components/AiInsightsCard.qml` |
| Secret Service, HTTP, provider differences, output validation | `scripts/lib/ai_insights.py` via `scripts/ai-insights.py` |
| Settings, key prompt, model discovery | `configAiInsights.qml` |

Nothing in this table runs while `aiInsightsEnabled` is false: the snapshot is
not built, the controller has no scheduled or active process, and the card is
hidden. Model discovery and wallet lookups run only from the settings page when
the user enables the feature or presses a button.

## Language

The request language is the language of the translation catalog that `i18n()`
actually resolved, not `Qt.locale()`, `Qt.uiLanguage`, the numeric locale, the
provider, or the model. Each catalog translates one marker message
(`msgctxt` "BCP 47 language tag of this translation...", `msgid` "en") to its own
tag: `it`, `de`, `fr`, `es`, or `pt-BR`. An interface without a catalog falls
back to English text and therefore English insights.

This matters in practice. Under `LANG=C.UTF-8 LANGUAGE=it`, gettext ignores
`LANGUAGE` and the widget displays English, while `Qt.locale().name` reports
`it_IT`. The `ai-insights-mismatch` smoke scenario reproduces that case and
requires the insight language to match the displayed text.

`AiInsights.languageTag` normalizes the marker to a bounded BCP 47 tag, the
command passes it as `--language`, and the helper writes it into the system
instructions with an English language name, for example `Write every sentence
in Italian (BCP 47 tag "it"), using that regional variety`. The language is
part of the cache context, so an insight generated in another language is
never shown as current. A language change does not make a request due by
itself; the next insight follows the configured generation policy.

## Snapshot contract

`AiInsightsSnapshot.build(providers, nowMs, warningPercent)` constructs a new
object from an allowlist. It never copies an input record.

```json
{
  "version": 1,
  "notes": "Quota percentages are per provider window. ...",
  "providers": [
    {"id": "codex",
     "quotas": [{"window": "primary", "usedPercent": 72, "windowHours": 5,
                 "resetsInHours": 2, "forecast": "runsOutBeforeReset",
                 "runsOutInHours": 1, "expectedUsedPercentNow": 40}],
     "spend": {"currency": "USD", "last7Days": 21, "previous7Days": 14,
               "changePercent": 50, "estimated": true},
     "tokens": {"last7Days": 14000, "previous7Days": 7000, "changePercent": 100},
     "incident": "major"}
  ],
  "signals": [{"kind": "quotaRunsOutBeforeReset", "provider": "codex",
               "window": "primary", "runsOutInHours": 1, "resetsInHours": 2}]
}
```

- Provider IDs must match `^[a-z0-9][a-z0-9._-]{0,63}$`. Titles, account
  identities, organizations, login methods, CLI prose, extra-window labels,
  detail rows, model names, projects, paths, sessions, and errors are never read.
- Only providers with a current measurement are listed. A stale (retained),
  unavailable, or empty provider is left out entirely, so retained numbers are
  never presented as current consumption and a model cannot mention a provider
  it has no data for. Without any current provider no request is made.
- Quotas are those rows with a known percentage, at most four per provider and
  eight providers. Forecasts come only from the CLI pace record already
  normalized by `ProviderNormalizer.rateWindowMetrics`; nothing is extrapolated.
- Spend and token comparisons require the cost history already loaded for the
  **Usage & Spend** range: all fourteen complete days before today, each with a
  finite amount, and established coverage. The history must reach today: a
  scan from before midnight, for example one kept across a suspend, saw only
  part of yesterday. Missing, unknown, or partial days produce no comparison.
  Amounts keep their ISO currency per provider and are never summed across
  providers. Spend keeps the qualifier the widget shows beside the amount:
  estimated or approximate sources, including an estimated share, set
  `estimated`, and partial amounts (unpriced or unmetered requests) or days
  with incomplete requests set `incomplete`. Opening the popup or generating
  an insight never starts a cost scan.
- Signals are deterministic: exhausted quota, forecast exhaustion before reset,
  quota at or above the warning threshold, a spend or token change of at least
  25% between the two periods, and a known service incident. An increase above
  300% carries `changeMultiple` (the ratio of the two periods) instead of
  `changePercent`, so the model never has to divide and sees only one form.
- The serialized snapshot is ASCII, at most 16 KiB, and identified by an FNV-1a
  hash. Automatic generation skips a request when the snapshot is identical to
  the cached insight's.

Privacy mode does not change this snapshot, because it already contains none
of the text privacy mode hides.

## Request contract

The helper sends one non-streaming request with two messages: fixed English
instructions and `Usage data:` followed by the snapshot JSON and a closing
reminder of the output language, which small models otherwise ignore. The instructions
require the selected language with its decimal separator, only provided facts,
no invented comparisons or forecasts, no cross-currency arithmetic, no
equivalence between provider percentages, and no filler or unnecessary advice.
The summary asks for one or two sentences of at most 30 words, and highlights of
at most 12 words must add facts the summary does not state; models count words
far better than characters. A `changeMultiple` is written as that multiple and
a `changePercent` exactly as given: models that convert percentages themselves
get the multiple wrong. The instructions end with the response JSON Schema, which
Ollama recommends alongside `format`. CLI-derived data is described as data,
never as instructions.

| Provider | Endpoint | Provider-specific fields |
| --- | --- | --- |
| Ollama | `POST {endpoint}/api/chat` | `format` JSON Schema, `stream: false`, `think: false`, `keep_alive: 0`, `temperature: 0`, `num_predict: 4000`, `num_ctx` for the whole prompt plus the output bound, no credentials |
| OpenRouter | `POST https://openrouter.ai/api/v1/chat/completions` | strict `json_schema`, `max_tokens: 4000`, `provider.require_parameters`, `provider.data_collection: "deny"`, optional `provider.zdr`, `reasoning: {"effort": "none"}` for reasoning models, `HTTP-Referer` and `X-OpenRouter-Title` app attribution |
| OpenAI | `POST https://api.openai.com/v1/chat/completions` | strict `json_schema`, `max_completion_tokens: 4000`, `store: false` |

Before an OpenRouter generation, the helper reads the model's public
`/models/{id}/endpoints` metadata without the key. Only when one endpoint lists
both `reasoning` and `structured_outputs` does the request turn reasoning off:
hidden reasoning is billed as output, and `require_parameters` routes only to an
endpoint that accepts every sent parameter. A failed lookup sends the request
without it. If privacy routing still leaves no endpoint (`model` or `routing`),
or the model rejects the parameter (`request`, for example a model whose
reasoning is mandatory), the request is retried once without it while at least
30 seconds of the time budget remain; neither failure reached a model or was
billed. Measured
with `deepseek/deepseek-v4.1-flash`, reasoning off cut output from about
1000 tokens to about 100. Ollama's `think: false` applies only to models that
allow it; models that always think, or accept only thinking levels, keep their
default and may still hit the output bound. Ollama's default context is 4096 tokens
on most computers, and a longer prompt silently loses its start, where the
instructions are, so `num_ctx` is sized from the prompt at two characters per
token plus the output bound.

OpenRouter routing never uses `models` fallbacks, and `openrouter/*` router
aliases are rejected, so a request cannot move to another model with weaker
privacy terms. Model discovery lists only OpenRouter models that advertise
`structured_outputs`, except `:batch` variants, which serve only the Batch
API; OpenAI chat model families that accept Chat Completions with a
`json_schema` response format, which excludes the Responses-only `-pro` and
deep-research models, GPT-4, GPT-4 Turbo, and GPT-3.5, `chatgpt-4o-latest`,
and GPT-4o snapshots before `2024-08-06`; and installed Ollama models.
No default cloud model is chosen and no price is claimed; users pick a model.

The expected answer is `{"summary": string, "highlights": [string]}`. The helper
accepts a fenced JSON block, then bounds the summary to 600 characters and at
most three 160-character highlights, strips control characters and Markdown
emphasis, and rejects malformed JSON, wrong types, empty or oversized content,
refusals, and truncation (`finish_reason`/`done_reason` `length`). QML validates
the reply again and renders it only through plain-text labels.

Failures map to bounded reasons: `missing_key`, `secret_unavailable`, `auth`
(401), `credits` (402, or OpenAI `insufficient_quota`), `forbidden` (403),
`model` (404, invalid or router model), `request` (400/422), `rate_limited`
(429, with `Retry-After` up to 24 hours), `timeout`, `network`, `routing`
(OpenRouter 503), `unavailable`, `refused`, `truncated`, `format`,
`invalid_input`, and `endpoint`. OpenRouter can report a provider failure as
`200 OK` with only an error object; its numeric code maps through the same
table, honoring the response's `Retry-After`, and a choice that finished with
`error` is `unavailable`. Remote error bodies are never shown.

## Credentials and destinations

- API keys are stored in the Secret Service (KWallet on Plasma 6) with
  `secret-tool`, under the attributes `application app.codexbar.plasma`,
  `service ai-insights`, and `provider <id>`. There is no plaintext fallback and
  no custom encryption; an unavailable wallet fails with `secret_unavailable`.
- The helper prompts with `kdialog --password` and passes the key to
  `secret-tool store` on stdin. Lookups happen inside the helper. The key never
  reaches QML, a command line, the environment, a URL, a log, a cache, or output.
- The `Authorization` header is added as an unredirected header, and every
  redirect is refused, so a key can only reach the pinned host.
- Cloud endpoints are fixed HTTPS URLs with default certificate verification.
  The Ollama endpoint accepts `https://` anywhere and `http://` only for
  `localhost`, `127.0.0.0/8`, or `::1`; user info, paths, queries, and fragments
  are rejected. The settings page labels a non-local endpoint as sending data
  to that address. A loopback endpoint ignores `http_proxy`/`https_proxy`, so
  data promised to stay on this computer never reaches a proxy.
- **Test connection** runs only the model listing (plus OpenRouter's key check):
  no paid inference. It reports whether the configured model is in the listed
  models (Ollama's untagged names match `:latest`) and never presents an
  unlisted model as working. OpenRouter's list proves structured-output
  support, not Zero Data Retention routing, which is checked on generation.
  Editing the Ollama address retires a running test and clears its result,
  which describes only the address it listed.

## Scheduling and lifecycle

- Disabled by default; once enabled, generation is manual until the user picks
  every 6 hours, every 12 hours, or daily.
- Usage refreshes, opening the popup, and a changed language never make a
  request due. The interval counts from both the last successful generation and
  the persisted last attempt, so a failed or timed-out request, which the
  provider may already have billed, also waits a full interval, including
  across plasmashell restarts.
- One request at a time, with a per-request nonce. The helper's HTTP timeout is
  150 seconds, the shell bound 180 seconds, and the QML deadline 185 seconds,
  which leaves room for reasoning models and slower local models. The whole
  generation, including a wallet unlock prompt, the model lookup, and a retry,
  shares a 170-second budget: each request waits only for what remains, and no
  request starts with less than 30 seconds left. If the shell bound still stops
  the helper, the card reports a timeout. Answers may
  use up to 4000 output tokens, including hidden reasoning tokens.
- Changing provider, model, endpoint, privacy routing, or language, disabling the
  feature, or destroying the widget retires the active request; its late reply
  is ignored. Stored insights from another context are not shown as current.
- Failures never touch usage data. Every failure waits a full interval (24
  hours in manual mode) before automatic generation; `rate_limited` also waits
  for `Retry-After` (at least five minutes, at most 24 hours). An explicit
  request waits only for `Retry-After`, so a replaced key or a started Ollama
  can be retried at once.
- The `Retry-After` deadline is persisted in the internal
  `aiInsightsRateLimit` key with the context it applies to, so a plasmashell
  restart cannot lift it for automatic or explicit requests. Another context
  ignores it, a deadline beyond 24 hours is void, and a success clears it.
- An insight older than the interval (24 hours in manual mode), or followed by a
  failed attempt, stays visible and is labeled out of date.

## Verification

- `tests/tst_ai_insights.qml`: language tags, context keys, cache validation and
  invalidation, schedule and restart rules, retry delays, command quoting, and
  reply validation, including markup that must stay literal.
- `tests/tst_ai_insights_snapshot.qml`: the allowlist against injected fields,
  that only current providers are sent, partial and complete history, currencies,
  signals, identity, and bounds.
- `tests/test_ai_insights.py`: the helper against a local HTTP server and fake
  `secret-tool`/`kdialog` executables, covering the request language for six
  catalogs, OpenRouter privacy routing, OpenAI storage, Ollama requests, every
  failure mapping, redirects, loopback proxy bypass, timeouts, malformed output,
  and key handling. It also compiles the shipped catalogs and runs `main.qml`'s
  language adapter to prove the catalog tag reaches `--language` under C and
  Italian regional locales.
- `tests/test_ai_insights_settings.py`: the settings page's helper reply
  handling with stubbed processes, including an Ollama address edited during
  or after **Test connection**, and the **Clear** button re-arming when a new
  insight is stored after a clear.
- `tests/test_ai_insights_controller.py`: the production controller through
  Plasma's executable DataSource with a recording helper, covering disabled,
  manual, duplicate, automatic, restart, language/model/disable changes during a
  request, failures, invalid commands, failed attempts and rate limits across
  restarts, and destruction.
- Smoke scenarios `ai-insights`, `ai-insights-it`, `ai-insights-mismatch`,
  `ai-insights-error`, `ai-insights-single`, `settings-ai-insights`, and
  `settings-ai-insights-narrow` run the real applet with a synthetic helper. The
  settings scenarios also check that a model is kept per provider while the
  page is open, that the stored-key row stays within the form width, and that
  a long model list opens as a height-capped, scrolling menu. The
  card scenarios start generation through the first-use **Generate insight**
  button and check that highlights stay collapsed until **Show details**. The
  `normal` scenario asserts that the card stays hidden and idle by default.

No test contacts a real AI service, wallet, or credential.
