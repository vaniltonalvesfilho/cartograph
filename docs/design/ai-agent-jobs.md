# AI agent jobs

**Status:** Planned (spec approved, not implemented) · **Updated:** 2026-07-08

## Overview

Jobs gain a new step that calls a Claude model (Anthropic Messages API). Because
job chaining already inlines referenced jobs (`use "<code>"`) into a single
execution with one shared `state`, a graph of jobs where each job contains an
`agent` step becomes **a graph of cooperating agents**: agent A writes its
answer into the state, the `use`d job B interpolates that answer into its own
prompt, `if/else` routes on agent verdicts, and the existing flow/graph
visualization shows the whole thing running live.

Nothing changes in the engine to make this work. The feature is four additive
pieces:

1. **`agent` step** — a new `Steps.Step` implementation that calls the
   Anthropic Messages API and writes the text response into the shared state.
2. **Anthropic credential per project** — an encrypted, write-only API key
   registered on a project, referenced from the DSL by public code
   (`anthropic-<suffix8>`), following the Slack webhook pattern exactly.
3. **Token accounting** — input/output tokens and estimated cost recorded per
   `step_execution` (new `metadata` jsonb column), plus a per-job token budget
   that fails the execution when exceeded.
4. **Frontend** — a credentials panel (clone of the Slack panel), a
   differentiated agent node in the flow/canvas graphs, and token/cost display
   in the execution detail.

Phase 2 (sketched only) exposes existing steps as Anthropic *tools* so an agent
can act, not just write text.

---

## Design

### 1. The `agent` step

New module `CartographBackend.Steps.AgentStep`, registered in
`Steps.Registry` (`@steps`), `name/0` returning `"agent"`. It appears
automatically in `GET /api/tasks/steps` (registry-driven) and in the in-app
docs page.

#### DSL syntax

The parser needs **no changes** — `agent` is an ordinary step with ordinary
params (`IDENT value`, values `STRING | BOOL | FLOAT | INT`; double-quoted
strings may contain literal newlines and `\n` escapes, so multi-line prompts
work today):

```text
reviewPipeline {
    step "agent" {
        secret "anthropic-uI0IOQ45",
        model "claude-opus-4-8",
        system "You are a strict code reviewer. Answer in English.",
        prompt "Review the following report and answer with a verdict.\n\n{{report}}",
        output "review",
        maxTokens 2048
    },
    if state["review"] != "" {
        step "notify" {
            secret "slack-uI0IOQ45",
            message "Agent review finished"
        }
    }
}
```

#### Params

| Param | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `secret` | string | **yes** | — | Public code of an Anthropic credential registered on the executing project (`anthropic-<suffix8>`). Same scoping and anti-enumeration rules as the `notify` step. |
| `prompt` | string | **yes** | — | User message. Supports `{{key}}` interpolation from the shared state (below). |
| `model` | string | no | `"claude-opus-4-8"` | Model ID forwarded verbatim to the API. Not allowlisted — unknown models fail at the API with a clear message; known models get cost estimation (see Pricing). |
| `system` | string | no | *(omitted)* | System prompt. Also interpolated with `{{key}}`. |
| `output` | string | no | `"agent_result"` | State key the response text is written to. |
| `maxTokens` | int | no | `4096` | `max_tokens` for the request. Step-validated to `1..16_000` (we do not stream in phase 1; larger values risk HTTP timeouts). |
| `temperature` | float | no | *(omitted)* | Forwarded only when present. **Footgun documented in the in-app docs:** Claude Opus 4.7+, Sonnet 5 and Fable reject `temperature` with HTTP 400 — on the default model, setting it fails the step with the API error. |

#### Prompt interpolation

`{{key}}` (also `{{ key }}`, inner whitespace trimmed) is replaced by
`state["key"]`:

- Binary values are inserted verbatim.
- Non-binary values (maps, lists, numbers, booleans) are inserted as
  `Jason.encode!/1` output.
- **A missing key fails the step** with
  `agent: prompt references unknown state key 'key'` — pipelines must be
  explicit about their inputs; silently inserting an empty string would produce
  garbage prompts that are hard to debug.
- There is no escape sequence in phase 1; a literal `{{` in a prompt is not
  supported (documented limitation).

Implementation: a small private regex-based renderer inside `AgentStep`
(`~r/\{\{\s*([^}]+?)\s*\}\}/`). No parser/DSL changes.

#### Execution semantics and error contract

`execute(ctx)` follows the `NotifyStep` shape (`with` chain, one generic
message for not-found/wrong-project):

1. Validate params (`secret` present, `prompt` present, `maxTokens` in range).
   Failures: `{:error, "agent: 'prompt' param is required"}` etc.
2. Resolve credential by code via `Agents.get_credential_by_code/1` and check
   `credential.project_id == ctx.project_id`. Both failure modes return the
   identical `agent: Anthropic credential '<code>' not found in this project`.
3. Interpolate `system` and `prompt` against `ctx.state`.
4. **Budget pre-check** (see § Budget). If the execution has already consumed
   its budget, fail without calling the API.
5. `StepContext.cancelled?/1` check, then call the API (below). The HTTP call
   itself is not cancellable mid-flight (accepted trade-off; the step re-checks
   cancellation on return and the Interpreter already marks the step STOPPED).
6. On HTTP/API error: `{:error, "agent: Anthropic API error: <detail>"}`.
   The API key never appears in any error or log.
7. On success, branch on `stop_reason`:
   - `"end_turn"` → concatenate all `content` blocks of `type: "text"`,
     `StepContext.put_state(ctx, output, text)`, record usage metadata,
     log `agent: <model> answered (in=<n> out=<m> tokens, ~$<cost>)` plus a
     200-char response preview at INFO, return `{:ok, ctx}`.
   - `"max_tokens"` → `{:error, "agent: response truncated at maxTokens=<n>; raise maxTokens or shorten the prompt"}`.
     Truncated output is *not* written to state — a silently truncated handoff
     corrupts downstream agents.
   - `"refusal"` → `{:error, "agent: the model declined this request (refusal)"}`.
   - anything else → `{:error, "agent: unexpected stop_reason '<reason>'"}`.

Token usage is recorded (step metadata + budget counter) **on every response
that carries `usage`**, including the `max_tokens`/`refusal` failure paths —
those tokens were billed and must count against the budget.

#### Anthropic HTTP client

`CartographBackend.Agents.AnthropicClient` mirrors
`Webhooks.SlackHttpClient` exactly — a behaviour + default `:httpc`
implementation, swappable via app env so the test suite **never** performs a
real LLM call:

```elixir
@callback create_message(api_key :: String.t(), body :: map()) ::
            {:ok, map()} | {:error, String.t()}

def impl, do: Application.get_env(:cartograph_backend, :anthropic_client, __MODULE__)
```

- Endpoint: `POST <base_url>/v1/messages`, where `base_url` comes from
  `Application.get_env(:cartograph_backend, :anthropic_base_url, "https://api.anthropic.com")`.
  The base URL is **server config only** — never user input (no SSRF surface;
  stricter than Slack, where the user supplies the URL).
- Headers: `x-api-key: <key>`, `anthropic-version: 2023-06-01`,
  `content-type: application/json`.
- Request body (phase 1, no streaming, no thinking config):

  ```json
  {
    "model": "claude-opus-4-8",
    "max_tokens": 4096,
    "system": "…",                    // omitted when not set
    "temperature": 0.7,               // omitted when not set
    "messages": [{"role": "user", "content": "…"}]
  }
  ```

- Response fields consumed: `content[]` (text blocks), `stop_reason`,
  `usage.input_tokens`, `usage.output_tokens`,
  `usage.cache_read_input_tokens` / `usage.cache_creation_input_tokens`
  (recorded if present).
- TLS options identical to `SlackHttpClient.ssl_opts/0` (`verify_peer`, OS
  cacerts, hostname check).
- Timeouts: `connect_timeout: 10_000`, `timeout: 240_000` (non-streaming LLM
  responses can take minutes; Oban `:executions` jobs are long-lived already).
- HTTP status handling: 2xx → decode; 400/401/403/404 → error with the API's
  `error.message` (no retry); 429/500/529 → one retry (see § Retry); error
  bodies are truncated to 300 chars in messages.

The test fake (`config/test.exs`) returns a canned successful response and
records calls, following the `slack_http_client` fake precedent. QA/E2E runs
must configure the fake — a broken job must never spend real tokens
(established project rule for external side effects).

### 2. Anthropic credential per project

Follows the `SlackWebhook` pattern piece by piece.

#### Schema and migration

`CartographBackend.Agents.AnthropicCredential`, table
`anthropic_credentials`:

```elixir
schema "anthropic_credentials" do
  field :name, :string
  field :code, :string                                   # "anthropic-<suffix8>"
  field :api_key_encrypted, :binary, redact: true
  field :api_key, :string, virtual: true, redact: true   # write-only input
  field :project_id, :integer
  timestamps()
end
```

Migration `20260708000026_create_anthropic_credentials.exs` (additive):

```elixir
create table(:anthropic_credentials) do
  add :name, :string, null: false
  add :code, :string, null: false
  add :api_key_encrypted, :binary, null: false
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  timestamps()
end

create unique_index(:anthropic_credentials, [:code])
create unique_index(:anthropic_credentials, [:project_id, :name])
```

(The `[:project_id, :name]` unique index doubles as the FK index, same as
`slack_webhooks`.)

Changeset rules (mirroring `SlackWebhook.changeset/2`):

- `name` required, 1..100 chars; `project_id` required.
- `api_key` required **on insert**; blank on update means "keep the stored
  key" (the API never echoes it back).
- Format validation `~r/^sk-ant-\S+$/` — Anthropic keys are `sk-ant-…`; this
  catches pasted garbage early, the way the Slack URL regex does.
- `code` generated once on insert via
  `Ids.generate_job_code(__MODULE__, "anthropic")`.
- `api_key` encrypted into `api_key_encrypted` with `Vault.encrypt/1`;
  decrypted only inside `AgentStep.execute/1` at call time, never logged,
  never serialized.

#### Context

`CartographBackend.Agents` (new context, also the home of `AnthropicClient`
and `Pricing`): `list_for_project/1`, `get/1`, `get_credential_by_code/1`,
`create/1`, `update/2`, `delete/1` — same shapes as `Webhooks`.

#### REST API

Routes and controller are a rename of `SlackWebhookController` (same
`with_project`/`with_<resource>` helpers, same status codes, same 404-not-403
for cross-project access):

```
GET    /api/projects/:project_id/anthropic-credentials      → :view
POST   /api/projects/:project_id/anthropic-credentials      → :manage_secrets
PUT    /api/projects/:project_id/anthropic-credentials/:id  → :manage_secrets
DELETE /api/projects/:project_id/anthropic-credentials/:id  → :manage_secrets
```

- `:view` for listing: Explorers writing DSL need the public codes; the key is
  never serialized.
- `:manage_secrets` (level 40, Navigator+) for create/update/delete —
  identical to Slack webhooks.
- Serializer `Serializers.anthropic_credential/1` returns
  `id, name, code, projectId, insertedAt, updatedAt` — **never** the key, not
  even a masked form. (A `keySet: true` flag is unnecessary because the key is
  mandatory on insert.)
- Payload envelope: `{"credential": {"name": …, "apiKey": …}}` (camelCase in,
  camelCase out, consistent with the rest of the API).

#### GraphQL

**None** — secrets management stays REST-only, matching the existing decision
for Slack webhooks and SMTP settings. This is a deliberate, documented
exception to the "GraphQL mirrors REST" standard: write-only secret CRUD on
GraphQL adds surface without a consumer (the dashboard panels use REST), and
keeping all secret writes on one code path simplifies audit. If a GraphQL
consumer appears, mirror all three secret resources at once.

### 3. Agent → agent handoff via `use`

**No changes to `Dsl.Expander` or `Engine.Interpreter`.** This is the crux of
the design and the reason the feature is cheap:

- The Expander already inlines a `use`d job's steps into one flat AST (cycle
  detection, depth/step limits, author-time authorization — all unchanged).
- The Interpreter already threads one `state` map through every step of the
  expanded execution.
- Therefore an `agent` step in job A and an `agent` step in job B (referenced
  with `use`) already share state: A writes `output "brief"`, B's prompt says
  `{{brief}}`.
- `Dsl.Flow` already renders `use` references as `job` container nodes, and
  step statuses stream over the existing `step_updated` subscription keyed by
  `flow_node_id` — the "watch agents cooperate on the graph" experience is the
  existing live flow view plus node styling (§ Frontend).

#### State-key conventions (documentation, not enforcement)

Published in the in-app docs page and this document:

- Each agent writes to an **explicit, role-named** key: `output "research"`,
  `output "review"`, `output "verdict"` — never two agents to the same key
  unless overwriting is intended (last writer wins, exactly like any other
  step).
- Keys prefixed with `__` are reserved for the engine (the budget counter uses
  `__agent_tokens__`; the Expander already uses a `__job__` meta param).
- **Routing pattern:** to branch on an agent's decision, instruct the model to
  answer with a single literal token and compare it in a condition:

  ```text
  step "agent" {
      secret "anthropic-xxxx",
      prompt "…Answer with exactly APPROVE or REJECT.",
      output "verdict"
  },
  if state["verdict"] == "APPROVE" { … } else { … }
  ```

  `Dsl.Condition` string equality already supports this. (Models occasionally
  add whitespace; the step trims leading/trailing whitespace from the response
  text before writing it to state — the only response post-processing we do.)

### 4. Cost and observability

#### Per-step usage: `metadata` jsonb on `step_execution`

Decision: **a generic jsonb `metadata` column**, not agent-specific columns and
not log parsing.

- Structured logs are not queryable and die with log retention; dedicated
  columns (`input_tokens`, …) pollute a hot generic table for one step type
  and force a migration per future step that wants telemetry.
- Migration `20260708000025_add_metadata_to_step_execution.exs` (additive):
  `add :metadata, :map, null: false, default: %{}`.
- `Executions` gains `put_step_metadata!(step_execution_id, map)` (deep-merge
  into the column). `AgentStep` calls it after every API response that carries
  `usage`; the Interpreter then broadcasts the final step as it already does,
  so live subscribers receive the usage without new plumbing.

Shape written by the agent step:

```json
{
  "agent": {
    "model": "claude-opus-4-8",
    "inputTokens": 1234,
    "outputTokens": 456,
    "cacheReadInputTokens": 0,
    "estimatedCostUsd": 0.0175,
    "stopReason": "end_turn",
    "durationMs": 8342
  }
}
```

Exposure (typed, not raw JSON, so REST and GraphQL stay mirror images):

- REST: `Serializers.step_execution/1` gains `agentUsage` — the camelCased
  `metadata["agent"]` map, or `null`.
- GraphQL: `object :step_execution` gains
  `field :agent_usage, :agent_usage` with a new
  `object :agent_usage` (`model`, `input_tokens`, `output_tokens`,
  `cache_read_input_tokens`, `estimated_cost_usd`, `stop_reason`,
  `duration_ms`), resolved from the metadata column. The `step_updated`
  subscription carries it automatically (same object type).

#### Pricing

`CartographBackend.Agents.Pricing` — a compile-time map of USD per million
tokens, with an `Updated:` comment and a single function
`estimate(model, input_tokens, output_tokens) :: float | nil`:

| Model | Input $/MTok | Output $/MTok |
|---|---|---|
| `claude-opus-4-8` / `claude-opus-4-7` / `claude-opus-4-6` | 5.00 | 25.00 |
| `claude-sonnet-5` / `claude-sonnet-4-6` | 3.00 | 15.00 |
| `claude-haiku-4-5` | 1.00 | 5.00 |
| `claude-fable-5` | 10.00 | 50.00 |

Unknown model → `nil` (`estimatedCostUsd` omitted; tokens are still recorded).
The UI labels the number "estimated" — this table is informational, not
billing.

#### Per-execution token budget

- Migration `20260708000027_add_agent_token_budget_to_task_definition.exs`:
  `add :agent_token_budget, :integer` (nullable) on `task_definitions`.
  `nil` → server default
  `Application.get_env(:cartograph_backend, :agent_token_budget_default, 200_000)`.
- Semantics: the budget of the **root job** of the execution applies to the
  whole expanded run — including agent steps inlined from `use`d jobs (they run
  under the root's execution, so this falls out of the design for free).
- Counting: cumulative `input_tokens + output_tokens` across all agent steps
  of the execution, accumulated in the shared state under the reserved key
  `"__agent_tokens__"` (no schema change, survives step-to-step because state
  does).
- Enforcement in `AgentStep`:
  - **Pre-call check:** if `state["__agent_tokens__"] >= budget`, fail with
    `agent: execution token budget exhausted (<used>/<budget> tokens)` without
    calling the API.
  - **Post-call:** add the response's usage; the *first call that crosses* the
    budget is allowed to finish (we cannot preempt a request mid-flight) and
    subsequent agent steps fail. This makes worst-case overshoot one
    `maxTokens` window, which is bounded and documented.
- A failed budget check fails the step → execution FAILED via the normal
  Interpreter path (failure e-mail notification included, no new code).
- The budget travels to `AgentStep` the same way `project_id` does: add
  `agent_token_budget` to `StepContext` (defaulted field; `ExecutorWorker`
  reads it from the `task_def` it already loads and passes it into
  `Interpreter.run/3` → `StepContext`). This is the **only** engine touch:
  one extra field threaded through `Interpreter.run`'s signature
  (`run(nodes, execution_id, project_id, opts \\ [])` — additive, existing
  callers unchanged).
- Exposure: `agentTokenBudget` on the task serializer + GraphQL task object +
  task create/update payloads (REST and GraphQL mutations), editable by
  whoever can edit the job (existing `:edit` cascade).

### 5. Retry and idempotency

LLM calls are expensive and non-deterministic; the policy is **fail fast,
retry manually**:

- `ExecutorWorker` keeps `max_attempts: 1`. Oban never re-runs an execution by
  itself, so a crashed run can never silently re-invoke the LLM. (Already true;
  the spec makes it load-bearing — do not raise `max_attempts` while agent
  steps exist without adding step-level idempotency.)
- Inside `AnthropicClient`: **at most one retry**, only for 429/529/500 and
  transport errors, with a 2s + jitter sleep. 4xx (invalid request, bad key,
  refusal) is never retried. Two total attempts is the ceiling — an overloaded
  API during a 50-step agent pipeline must not multiply cost.
- Both attempts' usage: only the responses actually received carry usage; a
  transport-failed attempt costs nothing recordable. Whatever usage arrives is
  recorded (see § Execution semantics).
- Manual re-run of an execution (existing feature) is a *new* execution and
  will pay for new LLM calls — this stays a deliberate user action. The
  execution-detail screen shows tokens/cost precisely so the user can judge
  before re-running.
- No response caching in phase 1 (prompt caching via `cache_control` is a
  possible phase 3 optimization for repeated system prompts; noted, not
  designed).

### 6. Tool use — phase 2 (direction only, not to be implemented now)

Goal: let an agent *act* through existing steps instead of only writing text.

- New optional param `tools "queryDatabase,transform"` — an explicit
  **allowlist** of registry step names, empty by default (no tools unless the
  author opts in, never "all steps").
- `AgentStep` becomes a bounded loop (`maxIterations`, default ~5): send
  request with `tools:` definitions derived from an Anthropic-tool metadata
  callback added to the `Step` behaviour (optional callback
  `tool_schema/0` → `%{description, input_schema}`); on
  `stop_reason: "tool_use"`, execute the named step through the Registry with
  a child `StepContext` (same state, same project, same logger), return the
  resulting state delta as the `tool_result`, continue the conversation.
- Each tool invocation is persisted as its own `step_execution` row (so the
  flow view shows the agent's actions live) — requires a small Interpreter
  hook to allocate nested step rows; to be designed in the phase 2 spec.
- Security gates to design then: per-step tool opt-in (a step must declare
  itself agent-safe), no `executeDatabase`/`notify` in the default safe set,
  tool loops count against the same token budget, and tool inputs are
  model-controlled and must be validated exactly like user input.

### 7. Frontend (apps/web)

#### Credentials panel

`AnthropicCredentialsPanelComponent` — a direct clone of
`slack-webhooks-panel.component.ts`, mounted next to it in the project view
(visible per the existing `manageSecrets` permission flag the API already
exposes):

- List: name + code (with copy button) + usage hint
  `In the DSL: step "agent" { secret "anthropic-xxxx" }`.
- Create: name + API key field (`type="password"`); update: blank key keeps
  the stored one (mirror of `slackWebhooks.urlKeep`).
- The key is never displayed after saving.

#### Graph / canvas differentiation

`flow-graph.model.ts` keeps its `GKind` union; differentiation is by **step
name**, not a new kind (no backend change): nodes with `kind === 'step'` and
`title === 'agent'` render with a distinct icon (sparkle/bot glyph in
`icon.component.ts`) and an accent border, in both `JobFlowComponent`
(read-only flow, live statuses via the existing `step_updated` subscription —
running agents pulse like any running step, which *is* the "watch agents
cooperate" view) and `JobCanvasComponent`/`job-graph` (editor). The canvas
node editor stays the generic key/value param editor; `job-form` adds `agent`
to the step name options it gets from `GET /api/tasks/steps` automatically.

#### Params form convenience

Phase 1 keeps the generic param editor but adds an "insert agent step"
template in the DSL editor / canvas palette that pre-fills
`secret`, `prompt`, `output` (same mechanism as existing step snippets in
`docs.component.ts` / editor helpers). A dedicated agent form (dropdown of
project credentials, model picker, prompt textarea) is a listed phase 3
nice-to-have.

#### Tokens and cost display

- `ExecutionDetailComponent`: for each step whose payload has `agentUsage`,
  render a chip `↑1.2k ↓456 tok · ~$0.018`; a footer line sums tokens and cost
  across steps client-side (the steps are already loaded — no new endpoint).
- `ExecutionHistoryComponent` (list) is unchanged in phase 1 (no aggregate
  column server-side; revisit if users ask).
- `task-edit` / job form: numeric field for `agentTokenBudget` with the
  server-default hint.

#### i18n

New keys in `en.ts` **and** `pt.ts`, following the `slackWebhooks.*` naming:
`anthropicCredentials.title|hint|add|empty|name|key|keyKeep|usage|invalidKey`,
`agent.tokens|estimatedCost|budget|budgetHint|totalUsage`. In-app docs page
(`docs.component.ts`) gains the `agent` step section (params table, handoff
conventions, budget behavior, the `temperature` footgun) in both languages.

### 8. Security summary

| Threat | Mitigation |
|---|---|
| API key exfiltration | Encrypted at rest (`Vault`, AES-256-GCM), `redact: true`, write-only API (never serialized, blank-keeps on update), decrypted only inside `AgentStep` at call time, never logged or included in error messages. |
| Cross-project use of a credential | Step checks `credential.project_id == ctx.project_id`; not-found and wrong-project return one identical error (no enumeration oracle) — same as `notify`. |
| Who can manage keys | `:manage_secrets` (Navigator+, level 40) via the existing cascade; listing codes needs `:view`. |
| SSRF | None new: the endpoint host is server config, never user input. Only `api.anthropic.com` is contacted (TLS verify_peer + hostname check, as Slack). |
| Prompt injection (agent output → next agent's prompt) | Inherent to the composition model; mitigations: (a) `system` is separate from interpolated `prompt` content, and docs instruct wrapping interpolated state in explicit delimiters (e.g. `<report>{{report}}</report>`); (b) phase 1 agents have **no tools** — a hijacked agent can only write text into state; (c) docs warn that feeding agent output into action steps (`notify`, `executeDatabase` params) is the author's trust decision, same as any state value; (d) phase 2 tool access is opt-in allowlist per step. |
| Secrets leaking into prompts | Docs rule: never put credentials in `state` / prompts — prompts and responses land in logs and the Anthropic API. Nothing in the engine puts secrets in state today. |
| Cost abuse / runaway loops | Per-execution token budget (default 200k) failing the run; Expander's existing depth/step caps bound the number of agent steps; `max_attempts: 1` + max-one HTTP retry bound multiplication. |
| Real calls from tests | `AnthropicClient.impl()` env-swap; test/E2E config must set the fake (hard project rule for external side effects). |

---

## Implementation phases

### Phase 1 — thin vertical slice (target of the first iteration)

Backend, in dependency order:

1. **backend-2:** migrations 25/26/27 (`metadata` on `step_execution`,
   `anthropic_credentials`, `agent_token_budget` on `task_definitions`);
   `Agents` context + `AnthropicCredential` schema; `AnthropicClient`
   behaviour + `:httpc` impl + test fake config; `Pricing`;
   `Executions.put_step_metadata!/2`; `AgentStep` + Registry entry;
   `StepContext.agent_token_budget` threading
   (`ExecutorWorker` → `Interpreter.run/4` → `StepContext`). Unit tests with
   the fake client (success, interpolation, missing key, budget, refusal,
   max_tokens, wrong-project secret).
2. **backend-1:** `AnthropicCredentialController` + routes + serializer
   (`anthropic_credential/1`, `agentUsage` on `step_execution/1`,
   `agentTokenBudget` on the task serializer); GraphQL `object :agent_usage`,
   `step_execution.agent_usage`, task field + mutation arg
   `agent_token_budget`. Controller tests mirroring the Slack ones.

Frontend:

3. **frontend-2:** `AnthropicCredentialsPanelComponent` (+ API service
   methods, models, i18n); `agentUsage` chips + totals in
   `ExecutionDetailComponent`; `agentTokenBudget` field in the job form; agent
   node styling in `job-flow`/`flow-graph`/`job-canvas`; agent snippet in the
   DSL editor; docs page section (EN + PT).

Then **reviewer** (contract adherence: camelCase, write-only key, authz
levels, no-real-HTTP tests) and **qa** (end-to-end with the fake client:
register credential → author two chained jobs with agents → run → watch live
graph → verify tokens/cost in execution detail → budget-exceeded run fails).

Acceptance criteria for phase 1:

- A Navigator can register an Anthropic key; the key is never visible again
  via any API.
- A job with `step "agent"` runs and the response text is available to later
  steps and to `use`-chained jobs' agents.
- The execution detail shows per-step tokens and estimated cost; a run
  exceeding the job's token budget ends FAILED with a clear step error.
- The flow view distinguishes agent nodes and animates their live status.
- The whole test suite passes with zero requests leaving the machine.

### Phase 2 — tool use (separate spec before implementation)

Direction in § 6. Requires its own design pass (nested step executions,
`Step.tool_schema/0` callback, safety review by the security agent).

### Phase 3 — nice-to-haves (unscheduled)

Dedicated agent param form; execution-list aggregate cost column; streaming
partial output into live logs; Anthropic prompt caching for stable system
prompts; per-project (not just per-job) budget ceilings.

---

## Trade-offs

- **State-mediated handoff over message-passing.** Agents communicate through
  the existing blackboard `state` rather than a new agent-conversation
  abstraction. Cheap, composes with `if/else` and every existing step, and the
  graph view needs no new data model — but there is no shared conversation
  history between agents (each call is stateless). Multi-turn agent dialogue
  would be a different feature.
- **Generic `metadata` jsonb over typed columns.** Slightly weaker DB-level
  guarantees, but one migration serves every future step's telemetry, and the
  API layer re-types it (`agentUsage`).
- **Budget as reserved state key over a DB counter.** Zero schema/engine cost
  and exactly scoped to one execution; the counter dies with the process — but
  so does the execution, so nothing is lost. Worst-case overshoot is one
  in-flight request, documented.
- **REST-only secret management** repeats the Slack precedent and contradicts
  the GraphQL-mirrors-REST standard; accepted and documented until a GraphQL
  consumer for secrets exists.
- **No model allowlist.** Model IDs change faster than releases; unknown
  models degrade to "no cost estimate" instead of blocking users.

## Open questions / future evolution

- Should the budget also cap **per-step** `maxTokens` more tightly than the
  16k validation cap? (Deferred: the execution budget dominates.)
- Aggregate cost reporting per project/month (needs a query over
  `step_execution.metadata`; jsonb GIN index if it becomes hot).
- Streaming: worth adding once someone watches a long generation in the live
  log view; requires swapping `:httpc` for a streaming-capable client and
  extending `LogBroadcaster` usage inside the step.
- When phase 2 lands, revisit whether `agent` deserves first-class AST
  treatment (e.g. its own node type for richer visualization of tool
  sub-steps).
