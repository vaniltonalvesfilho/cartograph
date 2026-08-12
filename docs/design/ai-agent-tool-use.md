# AI Agent Jobs — Phase 2: Tool Use

Status: **implemented**, except the `tools` multi-select in §7 — see the note
there. Supersedes the "direction only" sketch in §6 of
[ai-agent-jobs.md](ai-agent-jobs.md), which this document replaces as the
source of truth for tool use.

Phase 1 gave us an agent that *thinks*: it reads shared state through `{{key}}`
interpolation and writes one text answer back. Phase 2 lets it *act* — it can
call a small, explicitly allowlisted set of existing steps as Anthropic tools,
observe what they did to the shared state, and decide what to do next.

Nothing about the engine changes. An agent step is still one `step_execution`
in one job; the loop lives inside `AgentStep`.

---

## 1. Threat model first

Tool use hands a language model the ability to make our backend *do things*.
Two properties of the existing step set make this sharper than it looks:

- **Tool inputs are model-controlled.** A `tool_use` block's `input` is
  generated text. It must be validated exactly as if it came off an HTTP
  request from an unauthenticated user — because in effect it did.
- **Steps communicate through shared state, not return values.** `filter`
  reads `state["files"]`; `transform` reads `state["files"]` and writes
  `state["transformed"]`. A tool call therefore *mutates the job's state*,
  which later non-agent steps will read. A hijacked agent doesn't just return
  a bad string — it can poison the state that the rest of the job runs on.

The consequence is that the allowlist is the whole security story, and it gets
two independent gates (§3). Everything else here is defense in depth.

### Prompt injection is the live risk

`readDirectory` + `parseJson` means the agent can read file contents that
Cartograph did not author — an uploaded CSV, a vendor's XML. That content
lands in a `tool_result` inside the model's context, where it is
indistinguishable from instruction. An attacker who controls a file in the
project's data root can attempt to steer the agent.

We accept this risk with these mitigations, and document it:

- The blast radius is bounded by the allowlist: a hijacked agent cannot *call*
  a step that writes files, runs SQL, or posts to Slack.
- `SafePath.resolve/2` confines every path to the executing project.
- The iteration cap, the per-turn tool-call cap, and the shared token budget
  bound how long a hijacked agent can flail.
- Docs warn that feeding untrusted files to a tool-enabled agent is the job
  author's trust decision — the same warning Phase 1 carries for feeding agent
  output into action steps.

### Corrections from the security audit (2026-08-01)

An audit of the implementation refuted two claims this section originally
made. Both are recorded here because the reasoning that produced them is the
reasoning most likely to produce the next mistake.

**"`SafePath.resolve/2` confines every path" was false when written.**
`TransformStep` read `state["files"]` and called `File.read/1` directly, with
no confinement — the only step that touched disk without going through
`SafePath`. Since `parseJson` takes a model-chosen `result_key`, an agent
could write `state["files"]` with any path at all and have `transform` read
it: arbitrary file read as the BEAM user, including other projects' sandboxes
and `config/runtime.exs`. The hole predated Phase 2 (a job author could already
chain `parseJson` → `transform` → `writeOutput`), but Phase 2 handed the whole
chain to an attacker who merely controls a *file*. Fixed by resolving through
`SafePath` in `TransformStep.apply_transform/3`; regression tests in
`transform_step_test.exs`.

The general lesson: confinement asserted at the *param* boundary says nothing
about a value that arrives through *state*. Any new tool that reads a path
from state needs its own check.

**"It cannot write files or run SQL" was too strong.** True for direct calls,
false for outcomes. Because `writeOutput` sources its content from
`state["transformed"]` and `executeDatabase` binds its params from
`state[rows_from]`, an agent that can write arbitrary state keys steers what a
*later, non-agent* step writes to disk or to the database. §1's second bullet
already said state poisoning was the real risk; this bullet contradicted it.
The accurate statement is: **a hijacked agent cannot call a dangerous step, but
it can control the data a dangerous step later consumes.**

This is **not yet fixed** — see §10.

---

## 2. The `tool_schema/0` callback

`Steps.Step` gains one **optional** callback:

```elixir
@doc """
Anthropic tool definition for this step, or nil if the step must never be
exposed to an agent. Implementing this is an explicit assertion that the step
is safe to invoke with model-generated params.
"""
@callback tool_schema() :: %{description: String.t(), input_schema: map()} | nil

@optional_callbacks tool_schema: 0
```

A step that does not implement `tool_schema/0` can never be a tool. That is
the default, and it is the correct default — opting in is a deliberate act
that should come with a look at how the step validates its params.

`Registry` gains:

```elixir
@spec tool_capable() :: [String.t()]   # names of steps that implement tool_schema/0
@spec tool_schema(String.t()) :: {:ok, map()} | {:error, String.t()}
```

`tool_capable/0` is computed at compile time via
`function_exported?/3` after `Code.ensure_compiled!/1`.

### The Phase 2 safe set

Six steps. All read-only or pure — nothing writes to disk, touches a database,
or makes an outbound request.

| Step | Why it's safe | `input_schema` |
|---|---|---|
| `readDirectory` | Lists regular files. Path confined by `SafePath.resolve/2` to the project's data root. | `path` (string, optional, default `data/inbox`) |
| `filter` | Pure. Filters `state["files"]` by extension. | `extension` (string, optional, default `txt`) |
| `transform` | Reads file contents and writes `state["transformed"]`. No writes to disk. | `operation` (string, enum: the ops `TransformStep` supports) |
| `validate` | Pure. Format checks against state fields; no side effects. | `cep`/`cnpj`/`cpf`/`email`/`regex`/`telefone` (string, optional), `pattern` (string, optional) |
| `parseJson` | Reads one file, decodes, writes to state. `SafePath`-confined. | `path`, `file_key`, `root_path`, `result_key` (all string, optional) |
| `parseXml` | Same, for XML. `SafePath`-confined. | `path`, `file_key`, `result_key` (string, optional), `root_element` (string, **required**) |

Every schema is `{"type": "object", "properties": {...}, "required": [...]}`.
Descriptions are written *for the model* — they explain when to reach for the
tool, not just what it does, which measurably improves triggering.

### Steps that must never declare `tool_schema/0`

Enforced by a test that asserts `Registry.tool_capable/0` equals exactly the
six names above, so adding a step doesn't silently widen the agent's reach.

| Step | Why |
|---|---|
| `executeDatabase` | Arbitrary SQL writes. |
| `queryDatabase` | Read-only SQL, but the *query string* would be model-written — the agent could read any table the connection reaches. Revisit only with a least-privilege connection. |
| `notify` | Outbound POST to a Slack webhook. Irreversible, externally visible. |
| `writeOutput`, `writeJson`, `writeXml` | Disk writes. `SafePath` confines *where*, not *what* — a hijacked agent could corrupt project data. Candidate for Phase 3 behind an explicit opt-in. |
| `agent` | Recursion: an agent spawning agents multiplies cost without a cost ceiling that composes. |
| `delay` | Harmless but pointless; a tool the model can only waste time with. |

---

## 3. The two gates

A step is callable by a given agent step only if **both** hold:

1. **Code gate** — the step implements `tool_schema/0`.
2. **Author gate** — the DSL author named it in that agent step's `tools`
   param.

```
step "agent" {
    secret "anthropic-uI0IOQ45",
    prompt "Find every invoice in the inbox and summarise the totals.",
    tools "readDirectory,filter,parseJson",
    maxIterations 5,
    output "summary"
}
```

`tools` is a comma-separated allowlist, **empty by default**. No `tools` param
means no `tools` array in the request body, which means the model cannot emit
a `tool_use` block at all — Phase 1 behaviour, unchanged. There is no
`tools "*"`, deliberately.

Parsing rules:

- Split on `,`, trim, drop empties.
- Every name must be in `Registry.tool_capable/0`. An unknown or non-tool-capable
  name **fails the step before the API call** — a typo must not silently
  narrow the agent's toolset into a confusing failure mid-loop.
- Duplicates collapse.

`maxIterations` — integer, default `5`, hard cap `10`. One "iteration" is one
API call. A run that hits the cap fails the step (see §5).

---

## 4. The loop

`AgentStep.execute/1` becomes a bounded recursion over the conversation.

```
messages = [%{role: "user", content: rendered_prompt}]

loop(ctx, messages, iteration):
  1. iteration > max_iterations?          -> {:error, cap exhausted}
  2. budget exhausted?                    -> {:error, budget}   (existing check)
  3. cancelled?                           -> {:ok, ctx}         (existing check)
  4. POST /v1/messages with tools + messages
  5. record_usage/4                       (existing: metadata + __agent_tokens__)
  6. case stop_reason
       "end_turn"  -> write text to state[output], {:ok, ctx}
       "tool_use"  -> run the blocks, append two messages, loop(iteration + 1)
       "max_tokens" | "refusal" | other -> {:error, ...}   (existing clauses)
```

Steps 1–3 and 5 already exist; the request body gains `tools`, and the
`"tool_use"` clause is new.

### Executing a turn's tool calls

An assistant message may contain **several** `tool_use` blocks (parallel tool
use is on by default). The API contract is strict here and we follow it
exactly:

- Execute every block. Never drop one.
- Return **all** `tool_result` blocks in a **single** user message. Splitting
  them across messages trains the model to stop calling tools in parallel.
- Each `tool_result` carries the `tool_use_id` of its block.

Execution is **sequential**, in the order the blocks appear. This is not
laziness — because steps communicate through shared state, running
`filter` before the `readDirectory` it depends on produces a different result
than the reverse. Sequential-in-order is the only ordering with defined
semantics, and it matches how the interpreter runs the same steps.

For each block:

```elixir
# 1. Defense in depth: re-check the allowlist even though we only sent
#    allowlisted definitions. A model can hallucinate a tool name.
# 2. Resolve the module through Registry.
# 3. Build a child StepContext: same state, project_id, execution_id,
#    log fn and cancelled? fn as the agent's ctx; params = the block's
#    "input" map; step_execution_id = the child row (§6).
# 4. module.execute(child_ctx)
```

**State threads forward.** On `{:ok, child_ctx}` the agent's ctx takes
`child_ctx.state` before the next block runs, and carries it out of the loop.
This is what makes `readDirectory` → `filter` → `transform` work as tools at
all, and it is why §1 calls state mutation the real risk.

### What the model sees as a result

The `tool_result` content is the **state delta** — the keys the step added or
changed — encoded as JSON:

```json
{"files": ["data/inbox/a.json", "data/inbox/b.json"]}
```

Not the whole state: a job carrying a large `transformed` map would blow the
context window and the token budget on every subsequent turn. Rules:

- Diff `child_ctx.state` against the pre-call state; keep added/changed keys.
- Drop the reserved `__agent_tokens__` key.
- Encode with `Jason.encode!/1`, then truncate to **8000 characters**, appending
  `… (truncated, N keys total)` when it doesn't fit. A tool result is a
  summary for the model to reason over, not a data transfer channel — the real
  values are in state, where later steps read them.
- An empty delta returns `{}` with a note that the step made no state change
  (`validate` succeeds this way).

### Step failure is not job failure

`{:error, reason}` from a tool returns a `tool_result` with `is_error: true`
and `reason` as content, and **the loop continues**. The model can read the
error and adapt — try a different path, a different extension, or give up and
answer in text. Failing the whole job on the first bad tool call would make
the agent brittle in exactly the situations tool use exists to handle.

State is **not** threaded forward from a failed call — `child_ctx` is
discarded, matching the interpreter's own treatment of a failed step.

A cancelled execution mid-loop returns `{:ok, ctx}` immediately; the
interpreter marks the step STOPPED on return, as today.

---

## 5. Error and exit paths

| Condition | Outcome |
|---|---|
| `stop_reason: "end_turn"` | Trimmed text → `state[output]`. Success. |
| Iteration cap hit while still requesting tools | `{:error, "agent: reached maxIterations=N without a final answer"}`. Nothing written to state — a half-finished agent must not hand a partial answer downstream, same reasoning as the `max_tokens` clause in Phase 1. |
| Tool step returns `{:error, _}` | `tool_result` with `is_error: true`; loop continues. |
| Unknown / non-allowlisted tool name in a `tool_use` block | `tool_result` with `is_error: true` naming the available tools; loop continues. Never crashes. |
| More `tool_use` blocks in one turn than the per-turn cap (8) | The first 8 run; the rest come back as `is_error` results telling the model to ask for fewer. **Every block is answered** — the API rejects a turn whose `tool_result`s don't cover its `tool_use`s, so dropping the extras silently would turn the next request into an HTTP 400 the model cannot recover from. |
| `stop_reason: "max_tokens"` / `"refusal"` | Existing Phase 1 clauses, unchanged. |
| Budget exhausted before a turn | Existing clause. Note the budget is shared across the whole loop — tool turns are not free. |
| `stop_reason: "pause_turn"` | Falls to the existing "unexpected stop_reason" clause. We declare no server-side tools, so it should not occur. |

---

## 6. Nested `step_execution` rows

Each tool call is persisted as its own `step_execution` so the execution
history and the live flow graph show what the agent actually did.

**Migration** — `step_executions` gains:

```elixir
add :parent_step_execution_id, references(:step_executions, on_delete: :delete_all)
create index(:step_executions, [:parent_step_execution_id])
```

Nullable; every existing row keeps `nil`, meaning top-level.

**`Executions` context** gains `create_child_step!/4`:

```elixir
create_child_step!(execution_id, step_name, order, parent_step_execution_id)
```

`order` is scoped to the parent: children of one agent step number `1, 2, 3…`
in call order. It does not participate in the top-level sequence, so the
interpreter's ordering is untouched.

**Usage metadata accumulates.** A tool-use run makes one API call per turn and
every turn is billed into the *same* agent `step_execution` row, so
`inputTokens`, `outputTokens`, `durationMs` and `estimatedCostUsd` carry the
run's totals, plus a `turns` count. Writing only the last turn's numbers would
under-report a multi-turn agent everywhere the UI sums one figure per step.
`stopReason` stays the latest — it describes how the run ended.

Children go through the same status transitions and the same
`broadcast_step/1` dual channel (PubSub + Absinthe) as top-level steps, so the
UI paints them live with no new subscription. `AgentStep` owns these
transitions directly — the interpreter is not involved, which is why no
interpreter hook is needed after all. The Phase 1 sketch anticipated one; it
turns out `AgentStep` has everything it needs (`execution_id`, the log fn, the
cancellation fn) already on its `StepContext`.

Read paths (`REST`, GraphQL `steps` field) must expose
`parentStepExecutionId` and keep returning children in the flat list;
grouping is the frontend's job.

---

## 7. Frontend (apps/web)

Deliberately minimal in this phase — the backend is the risky part.

- **execution-detail** — child rows render indented under their parent agent
  step, with the tool name and its error when it failed. Reuses the existing
  step row component; grouping is a `parentStepExecutionId` bucket in the
  component, not a new API shape.
- **job-form** — **not implemented.** The plan was a `tools` multi-select on the
  agent step, populated from a new read-only endpoint exposing
  `Registry.tool_capable/0` plus each schema's description (hardcoding the six
  names in the frontend would rot the moment the safe set changes). It has no
  natural home yet: step params are authored either as DSL text or as free-form
  key/value pairs on a canvas node, neither of which knows a step's param
  schema. A per-step-type param form is its own piece of work; until then
  `tools` is typed by hand and the backend rejects a bad name before any API
  call (§3), which is the failure mode that actually matters.
- **flow-graph / job-canvas** — unchanged this phase. Agent nodes already
  carry the purple border + `✦` glyph; nesting tool calls into the graph is a
  layout problem worth its own pass.
- **docs component** — a `tools` / `maxIterations` subsection under the
  existing `agent` section, EN + PT, including the prompt-injection warning
  from §1.

---

## 8. Testing

The suite must never spend real tokens — the `AnthropicClient` behaviour +
app-env fake from Phase 1 already guarantees this, and the fake grows the
ability to script a **sequence** of responses so a multi-turn loop can be
driven deterministically.

Cases that must exist:

- Single tool call → `end_turn`. Asserts state threading and the child row.
- Two `tool_use` blocks in one response → both executed in order, **one** user
  message carrying both `tool_result`s.
- Tool returns `{:error, _}` → `is_error: true`, loop continues, state not
  threaded from the failed call.
- Hallucinated tool name → `is_error` result, no crash.
- `tools` naming a non-tool-capable step (`notify`) → step fails before any
  API call.
- No `tools` param → request body has no `tools` key (Phase 1 parity).
- Iteration cap → error, nothing written to `state[output]`.
- Token budget exhausted mid-loop → error, usage still persisted.
- `Registry.tool_capable/0` equals exactly the six-name safe set.
- Cancellation mid-loop → `{:ok, ctx}`, no further API calls.

---

## 10. Open: constraining which state keys a tool may write

The one audit finding left unfixed, because the fix is a design choice rather
than a patch.

`parseJson` and `parseXml` take a model-chosen `result_key`, so a tool call can
write *any* state key. That is how an agent steers a later `writeOutput` or
`executeDatabase` (see the audit corrections in §1). The reserved
`__agent_tokens__` counter is now protected explicitly (`guard_reserved/2`),
but that is a patch on one key, not a rule.

Three candidate rules, roughly in increasing cost:

1. **Author-declared writable keys** — a `toolStateKeys "rows,files"` param on
   the agent step. Explicit and auditable; more DSL surface, and authors will
   get it wrong by being generous.
2. **Namespace tool writes** — tool-written keys land under an `agent.` prefix.
   Clean isolation, but it breaks the chaining that makes the tools useful at
   all (`filter` reads `state["files"]`, which `readDirectory` wrote).
3. **Fix the consuming steps instead** — make `writeOutput` and
   `executeDatabase` take their source key as an explicit author param rather
   than a convention. Attacks the problem where it actually lives, and helps
   non-agent jobs too; touches steps outside this feature.

(3) is the most honest fix and (1) the cheapest. Not decided.

## 9. Out of scope

- Write-capable tools (`writeOutput`, `writeJson`, `writeXml`).
- `queryDatabase` as a tool.
- Sub-agents / agent-as-tool.
- Streaming responses.
- Prompt caching of the tool definitions (`cache_control`) — a real cost win
  once the schemas stabilise, but it is an optimisation, not a capability.
- Tool calls as nodes in the flow graph.
