defmodule CartographBackend.Steps.AgentStep do
  @moduledoc """
  Calls a Claude model (Anthropic Messages API) and writes the text response
  into the shared state, so later steps — and `use`-chained jobs' agents —
  can read it.

      step "agent" {
          secret "anthropic-uI0IOQ45",
          model "claude-opus-4-8",
          system "You are a strict code reviewer. Answer in English.",
          prompt "Review the following report.\\n\\n{{report}}",
          output "review",
          maxTokens 2048
      }

  `secret` is the public code of an Anthropic credential registered on the
  executing project — credentials from other projects are not reachable, and
  the "not found" and "wrong project" cases share one error message so codes
  cannot be enumerated. `{{key}}` in `prompt`/`system` is replaced by
  `state["key"]`; a missing key fails the step. The response text (trimmed)
  goes to `state[output]` (default `"agent_result"`), and token usage plus
  estimated cost are recorded on the step's `metadata`.

  Note: Claude Opus 4.7+, Sonnet 5 and Fable reject `temperature` with
  HTTP 400 — on the default model, setting it fails the step with the API
  error. Every response that carries `usage` counts against the execution's
  agent token budget, including the `max_tokens`/`refusal` failure paths.

  ## Tool use

  With the optional `tools` param the agent can *act* through a small set of
  existing steps instead of only writing text:

      step "agent" {
          secret "anthropic-uI0IOQ45",
          prompt "Find every invoice in the inbox and summarise the totals.",
          tools "readDirectory,filter,parseJson",
          maxIterations 5,
          output "summary"
      }

  `tools` is an explicit allowlist, **empty by default** — with no `tools`
  param the request carries no tool definitions and the model cannot call
  anything. A step is reachable only if it also declares `tool_schema/0`
  (see `Steps.Step`), so there are two independent gates.

  Each tool call runs the real step against the *shared state* and is persisted
  as a child `step_execution`, so the execution history and the live flow graph
  show what the agent did. Because steps communicate through state (`filter`
  reads `state["files"]`), calls run sequentially in block order and the state
  threads forward between them.

  A failing tool returns an error result to the model and the loop continues —
  the agent can adapt. Running out of iterations fails the step.

  Every state key a tool call writes is recorded as agent-written (see
  `Engine.Provenance`), because `parseJson` takes a model-chosen `result_key`
  and could otherwise steer what a later `writeJson` or `executeDatabase`
  acts on. Those steps then refuse the key unless the job author wrote
  `allowAgentData true` on them. Full design and threat model:
  `docs/design/ai-agent-tool-use.md`.
  """
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Agents
  alias CartographBackend.Agents.{AnthropicClient, Pricing}
  alias CartographBackend.Engine.{LogBroadcaster, Provenance, StepBroadcaster, StepContext}
  alias CartographBackend.Executions.Status
  alias CartographBackend.Steps.Registry
  alias CartographBackend.{Executions, Vault}

  @default_model "claude-opus-4-8"
  @default_output "agent_result"
  @default_max_tokens 4096
  # We do not stream in phase 1; larger values risk HTTP timeouts.
  @max_tokens_cap 16_000

  @default_max_iterations 5
  # One iteration is one API call. The cap bounds both cost and how long a
  # misbehaving (or hijacked) agent can keep calling tools.
  @max_iterations_cap 10

  # A tool result is a summary for the model to reason over, not a data
  # transfer channel — the real values live in the shared state, where later
  # steps read them. Without this cap a large `transformed` map would be
  # re-sent, and re-billed, on every subsequent turn.
  @tool_result_limit 8_000

  # A single response may carry any number of tool_use blocks, and each one is
  # a real step plus a DB row plus broadcasts. Cap the fan-out per turn.
  @max_tool_calls_per_turn 8

  # Model-written params are echoed into the execution log, which project
  # members can read — truncate so a hijacked agent cannot use it to dump a
  # file it read into durable, widely-visible storage.
  @logged_input_limit 500

  # Reserved state key: cumulative input+output tokens of all agent steps of
  # the execution. Survives step to step because state does.
  @tokens_key "__agent_tokens__"

  # `{{key}}` (also `{{ key }}`, inner whitespace trimmed).
  @interpolation ~r/\{\{\s*([^}]+?)\s*\}\}/

  @impl true
  def name, do: "agent"

  @impl true
  def execute(%StepContext{params: params, project_id: project_id} = ctx) do
    code = Map.get(params, "secret")
    prompt = Map.get(params, "prompt")

    with {:secret, true} <- {:secret, is_binary(code) and code != ""},
         {:prompt, true} <- {:prompt, is_binary(prompt) and prompt != ""},
         {:max_tokens, {:ok, max_tokens}} <- {:max_tokens, fetch_max_tokens(params)},
         # Both tool params are validated before the credential is even looked
         # up: a typo in `tools` must fail loudly here, never silently narrow
         # the agent's toolset into a confusing mid-loop failure.
         {:tools, {:ok, tool_names}} <- {:tools, fetch_tools(params)},
         {:iterations, {:ok, max_iterations}} <- {:iterations, fetch_max_iterations(params)},
         {:credential, {:ok, credential}} <- {:credential, fetch_credential(code, project_id)},
         {:render, {:ok, system}} <-
           {:render, interpolate(Map.get(params, "system"), ctx, "system")},
         {:render, {:ok, rendered_prompt}} <- {:render, interpolate(prompt, ctx, "prompt")},
         {:budget, :ok} <- {:budget, check_budget(ctx)} do
      if StepContext.cancelled?(ctx) do
        # Don't spend tokens on a stopped run; the Interpreter marks the step
        # STOPPED on return.
        {:ok, ctx}
      else
        run = %{
          credential: credential,
          base: build_body(params, max_tokens, system, tool_names),
          allowed: tool_names,
          max_iterations: max_iterations
        }

        messages = [%{"role" => "user", "content" => rendered_prompt}]
        loop(ctx, run, messages, _iteration = 1, _child_order = 1)
      end
    else
      {:secret, false} ->
        {:error,
         "agent: 'secret' param is required (the Anthropic credential code, e.g. anthropic-uI0IOQ45)"}

      {:prompt, false} ->
        {:error, "agent: 'prompt' param is required"}

      {:max_tokens, {:error, reason}} ->
        {:error, reason}

      {:tools, {:error, reason}} ->
        {:error, reason}

      {:iterations, {:error, reason}} ->
        {:error, reason}

      {:credential, {:error, _}} ->
        {:error, not_accessible(code)}

      {:render, {:error, reason}} ->
        {:error, reason}

      {:budget, {:error, reason}} ->
        {:error, reason}
    end
  end

  # ── Conversation loop ────────────────────────────────────────────────────────

  # One iteration is one API call. Recurses only on `tool_use`; every other
  # stop reason is terminal.
  defp loop(ctx, run, messages, iteration, child_order) do
    cond do
      iteration > run.max_iterations ->
        {:error,
         "agent: reached maxIterations=#{run.max_iterations} without a final answer; " <>
           "raise maxIterations or narrow the task"}

      StepContext.cancelled?(ctx) ->
        {:ok, ctx}

      true ->
        case check_budget(ctx) do
          {:error, reason} ->
            {:error, reason}

          :ok ->
            body = Map.put(run.base, "messages", messages)

            case call_api(ctx, run.credential, body) do
              {:error, reason} ->
                {:error, reason}

              {:ok, ctx, response, usage} ->
                handle_response(ctx, run, messages, iteration, child_order, response, usage)
            end
        end
    end
  end

  # ── Param handling ───────────────────────────────────────────────────────────

  defp fetch_max_tokens(params) do
    case Map.get(params, "maxTokens", @default_max_tokens) do
      n when is_integer(n) and n >= 1 and n <= @max_tokens_cap ->
        {:ok, n}

      _ ->
        {:error, "agent: 'maxTokens' must be an integer between 1 and #{@max_tokens_cap}"}
    end
  end

  # Not-found and wrong-project share one path (and one message below) so
  # credential codes cannot be enumerated across projects — same as `notify`.
  defp fetch_credential(code, project_id) do
    with {:ok, credential} <- Agents.get_credential_by_code(code),
         true <- credential.project_id == project_id do
      {:ok, credential}
    else
      _ -> {:error, :not_accessible}
    end
  end

  defp not_accessible(code),
    do: "agent: Anthropic credential '#{code}' not found in this project"

  defp output_key(params) do
    case Map.get(params, "output") do
      key when is_binary(key) and key != "" -> key
      _ -> @default_output
    end
  end

  defp fetch_max_iterations(params) do
    case Map.get(params, "maxIterations", @default_max_iterations) do
      n when is_integer(n) and n >= 1 and n <= @max_iterations_cap ->
        {:ok, n}

      _ ->
        {:error, "agent: 'maxIterations' must be an integer between 1 and #{@max_iterations_cap}"}
    end
  end

  # The author gate. Absent or empty means no tools at all — the request then
  # carries no `tools` key and the model cannot emit a tool_use block. There
  # is deliberately no wildcard.
  defp fetch_tools(params) do
    case Map.get(params, "tools") do
      nil ->
        {:ok, []}

      value when is_binary(value) ->
        names =
          value
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        case Enum.reject(names, &(&1 in Registry.tool_capable())) do
          [] ->
            {:ok, names}

          rejected ->
            {:error,
             "agent: 'tools' names step(s) not available to agents: #{Enum.join(rejected, ", ")}. " <>
               "Available: #{Registry.tool_capable() |> Enum.join(", ")}"}
        end

      _ ->
        {:error, "agent: 'tools' must be a comma-separated list of step names"}
    end
  end

  # Anthropic tool definitions for the allowlisted steps. Each step owns its
  # own schema, so the wire format stays next to the validation it describes.
  defp tool_definitions(names) do
    Enum.map(names, fn name ->
      {:ok, schema} = Registry.tool_schema(name)

      %{
        "name" => name,
        "description" => schema.description,
        "input_schema" => schema.input_schema
      }
    end)
  end

  # `messages` is set per iteration by the loop; everything else is fixed for
  # the run, which also keeps the cacheable prefix (tools, then system) stable.
  defp build_body(params, max_tokens, system, tool_names) do
    %{
      "model" => model(params),
      "max_tokens" => max_tokens
    }
    |> maybe_put("system", system)
    |> maybe_put("temperature", numeric_param(params, "temperature"))
    |> maybe_put("tools", if(tool_names == [], do: nil, else: tool_definitions(tool_names)))
  end

  defp model(params) do
    case Map.get(params, "model") do
      m when is_binary(m) and m != "" -> m
      _ -> @default_model
    end
  end

  defp numeric_param(params, key) do
    case Map.get(params, key) do
      n when is_number(n) -> n
      _ -> nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ── Prompt interpolation ─────────────────────────────────────────────────────

  # A missing key fails the step: pipelines must be explicit about their
  # inputs; a silently inserted empty string would produce garbage prompts.
  defp interpolate(nil, _ctx, _field), do: {:ok, nil}

  defp interpolate(text, %StepContext{state: state}, field) when is_binary(text) do
    keys = @interpolation |> Regex.scan(text) |> Enum.map(fn [_, key] -> key end)

    case Enum.find(keys, &(not Map.has_key?(state, &1))) do
      nil ->
        rendered =
          Regex.replace(@interpolation, text, fn _match, key ->
            render_value(Map.fetch!(state, key))
          end)

        {:ok, rendered}

      missing ->
        {:error, "agent: #{field} references unknown state key '#{missing}'"}
    end
  end

  defp render_value(value) when is_binary(value), do: value
  defp render_value(value), do: Jason.encode!(value)

  # ── Budget ───────────────────────────────────────────────────────────────────

  # Pre-call check only: the first call that crosses the budget is allowed to
  # finish (a request in flight cannot be preempted) and subsequent agent
  # steps fail — worst-case overshoot is one maxTokens window.
  defp check_budget(ctx) do
    used = tokens_used(ctx)
    budget = effective_budget(ctx)

    if used >= budget do
      {:error, "agent: execution token budget exhausted (#{used}/#{budget} tokens)"}
    else
      :ok
    end
  end

  # Defensive: the counter lives in the shared state, which an earlier step in
  # the job may have written. A non-integer there would make the budget
  # comparison meaningless (Erlang term ordering compares any two terms), so
  # anything unexpected is treated as "nothing spent yet".
  defp tokens_used(ctx) do
    case StepContext.get_state(ctx, @tokens_key, 0) do
      n when is_integer(n) and n >= 0 -> n
      _ -> 0
    end
  end

  defp effective_budget(%StepContext{agent_token_budget: nil}),
    do: Application.get_env(:cartograph_backend, :agent_token_budget_default, 200_000)

  defp effective_budget(%StepContext{agent_token_budget: budget}), do: budget

  # ── API call and response handling ───────────────────────────────────────────

  defp call_api(ctx, credential, body) do
    # Decrypted only here, at call time; never logged, never in errors.
    api_key = Vault.decrypt(credential.api_key_encrypted)
    started = System.monotonic_time(:millisecond)

    case AnthropicClient.impl().create_message(api_key, body) do
      {:error, detail} ->
        {:error, "agent: Anthropic API error: #{detail}"}

      {:ok, response} ->
        duration_ms = System.monotonic_time(:millisecond) - started
        # Usage is recorded (metadata + budget counter) for every response
        # that carries it — max_tokens/refusal tokens were billed too. On a
        # multi-turn run this accumulates across every iteration.
        {ctx, usage} = record_usage(ctx, body["model"], response, duration_ms)
        {:ok, ctx, response, usage}
    end
  end

  # ── Response handling ────────────────────────────────────────────────────────

  # The model wants to act. Run every tool_use block in the turn, then feed all
  # results back in a single user message and go round again.
  defp handle_response(
         ctx,
         run,
         messages,
         iteration,
         child_order,
         %{"stop_reason" => "tool_use"} = response,
         usage
       ) do
    content = response |> Map.get("content") |> List.wrap()
    StepContext.info(ctx, answered_line(run.base["model"], usage) <> " — calling tools")
    log_text_blocks(ctx, content)

    blocks = Enum.filter(content, &(is_map(&1) and &1["type"] == "tool_use"))

    {ctx, results, next_child_order} = run_tool_blocks(ctx, run, blocks, child_order)

    # All results go back in ONE user message: splitting them across messages
    # trains the model out of requesting tools in parallel.
    messages =
      messages ++
        [
          %{"role" => "assistant", "content" => content},
          %{"role" => "user", "content" => results}
        ]

    loop(ctx, run, messages, iteration + 1, next_child_order)
  end

  defp handle_response(ctx, run, _messages, _iteration, _child_order, response, usage) do
    handle_final(ctx, response, usage, run.base)
  end

  defp handle_final(ctx, %{"stop_reason" => "end_turn"} = response, usage, body) do
    text =
      response
      |> Map.get("content")
      |> List.wrap()
      |> Enum.filter(&(is_map(&1) and &1["type"] == "text"))
      |> Enum.map_join("", & &1["text"])
      # Models occasionally add whitespace around single-token answers; this
      # trim is the only response post-processing we do.
      |> String.trim()

    ctx = StepContext.put_state(ctx, output_key(ctx.params), text)
    StepContext.info(ctx, answered_line(body["model"], usage))
    StepContext.info(ctx, "agent: response preview: #{String.slice(text, 0, 200)}")
    {:ok, ctx}
  end

  # The failure clauses below drop `ctx` on purpose. `record_usage/4` already
  # ran (before this function), so the billed tokens are durably persisted on
  # the step's `metadata` — that is the authoritative usage record. It also
  # bumped the in-state `__agent_tokens__` budget counter, but returning
  # `{:error, _}` discards this ctx: the Interpreter halts the whole run on a
  # step error (`walk_nodes` → `{:halt, err}`), so no later agent step can read
  # the counter anyway. This is correct only as long as a step error aborts the
  # execution; a future continue-on-error mode would need the counter threaded
  # through the engine's error path (see interpreter.ex).

  # Truncated output is not written to state — a silently truncated handoff
  # corrupts downstream agents.
  defp handle_final(_ctx, %{"stop_reason" => "max_tokens"}, _usage, body) do
    {:error,
     "agent: response truncated at maxTokens=#{body["max_tokens"]}; raise maxTokens or shorten the prompt"}
  end

  defp handle_final(_ctx, %{"stop_reason" => "refusal"}, _usage, _body) do
    {:error, "agent: the model declined this request (refusal)"}
  end

  defp handle_final(_ctx, response, _usage, _body) do
    {:error, "agent: unexpected stop_reason '#{Map.get(response, "stop_reason")}'"}
  end

  # ── Tool execution ───────────────────────────────────────────────────────────

  # Sequential and in block order, on purpose: steps talk to each other through
  # the shared state (`filter` reads state["files"]), so running them in any
  # other order — or concurrently — has no defined meaning. State threads from
  # one call into the next, exactly as the Interpreter threads it between steps.
  defp run_tool_blocks(ctx, run, blocks, child_order) do
    {kept, dropped} = Enum.split(blocks, @max_tool_calls_per_turn)

    if dropped != [] do
      StepContext.error(
        ctx,
        "agent: refused #{length(dropped)} tool call(s) over the per-turn cap of " <>
          "#{@max_tool_calls_per_turn}"
      )
    end

    {ctx, results, next_order} =
      Enum.reduce(kept, {ctx, [], child_order}, fn block, {ctx, results, order} ->
        # Checked between calls, not just per iteration: a turn asking for many
        # tools would otherwise be uncancellable.
        if StepContext.cancelled?(ctx) do
          {ctx, results ++ [error_result(block["id"], "Execution was stopped.")], order}
        else
          {ctx, result} = run_tool_block(ctx, run, block, order)
          {ctx, results ++ [result], order + 1}
        end
      end)

    # Every tool_use block must come back with a tool_result: the API rejects a
    # turn whose results don't cover its calls. Dropping the ones over the cap
    # silently would turn the next request into an HTTP 400 instead of a
    # refusal the model can read and retry with fewer calls.
    refused =
      Enum.map(dropped, fn block ->
        error_result(
          block["id"],
          "Refused: this turn requested more than #{@max_tool_calls_per_turn} tool calls. " <>
            "Ask for fewer at a time."
        )
      end)

    {ctx, results ++ refused, next_order}
  end

  defp run_tool_block(ctx, run, block, order) do
    name = block["name"]
    id = block["id"]
    input = if is_map(block["input"]), do: block["input"], else: %{}

    # Defense in depth: we only ever sent the allowlisted definitions, but a
    # model can hallucinate a name. An unknown tool is an error result the
    # agent can recover from, never a crash.
    if name in run.allowed do
      execute_tool(ctx, name, id, input, order)
    else
      StepContext.error(ctx, "agent: refused unlisted tool '#{name}'")

      {ctx,
       error_result(
         id,
         "Tool '#{name}' is not available. Available tools: #{Enum.join(run.allowed, ", ")}"
       )}
    end
  end

  defp execute_tool(ctx, name, id, input, order) do
    {:ok, module} = Registry.get(name)

    child =
      Executions.create_child_step!(ctx.execution_id, name, order, ctx.step_execution_id)
      |> StepBroadcaster.broadcast()

    child = set_child_status(child, Status.running())

    StepContext.info(
      ctx,
      "agent: calling tool '#{name}' #{String.slice(Jason.encode!(input), 0, @logged_input_limit)}"
    )

    # Params come straight from the model, so the step's own validation is the
    # security boundary — same code path a job author's literal params take.
    # Logs are rebound to the child row so the UI attributes them correctly.
    child_ctx = %StepContext{
      ctx
      | params: input,
        step_execution_id: child.id,
        log: fn level, msg -> LogBroadcaster.log(ctx.execution_id, child.id, level, msg) end
    }

    # A step's params are normally shaped by the DSL parser; here they are
    # whatever the model emitted, so a type the step never expected raises
    # rather than returning {:error, _}. Without this the exception escapes to
    # the worker, fails the whole execution, and leaves both this row and the
    # agent's own row stuck in RUNNING.
    result =
      try do
        module.execute(child_ctx)
      rescue
        error -> {:error, "#{name} raised: #{Exception.message(error)}"}
      catch
        :exit, reason -> {:error, "#{name} exited: #{inspect(reason)}"}
      end

    case result do
      {:ok, new_ctx} ->
        set_child_status(child, Status.success())
        delta = state_delta(ctx.state, new_ctx.state)
        StepContext.info(ctx, "agent: tool '#{name}' ok, changed #{map_size(delta)} state key(s)")

        # Everything this call touched is model-chosen data from here on: the
        # keys are recorded so a later writeOutput/writeJson/writeXml/
        # executeDatabase refuses them unless the author said otherwise.
        state =
          ctx.state
          |> Provenance.guard_reserved(new_ctx.state)
          |> Provenance.mark_agent_written(Map.keys(delta))

        {%{ctx | state: state}, ok_result(id, delta)}

      {:error, reason} ->
        set_child_status(child, Status.failed(), reason)
        StepContext.error(ctx, "agent: tool '#{name}' failed: #{reason}")
        # State is NOT threaded forward from a failed call — the Interpreter
        # discards a failed step's ctx too. The model sees the error and can
        # adapt; the job does not fail.
        {ctx, error_result(id, reason)}
    end
  end

  defp set_child_status(step, status, error \\ nil) do
    step
    |> Executions.update_step_status!(status, error)
    |> StepBroadcaster.broadcast()
  end

  # ── Tool results ─────────────────────────────────────────────────────────────

  # Only what the step actually changed. Sending the whole state would re-send
  # (and re-bill) every prior tool's output on every remaining turn. The
  # reserved namespace is engine bookkeeping — the model never sees it, and
  # `guard_reserved/2` means a tool cannot have changed it anyway.
  defp state_delta(before, after_state) do
    after_state
    |> Enum.reject(fn {key, value} ->
      Provenance.reserved?(key) or Map.get(before, key) == value
    end)
    |> Map.new()
  end

  defp ok_result(id, delta) when map_size(delta) == 0 do
    result_block(id, "Step succeeded and made no change to the shared state.")
  end

  defp ok_result(id, delta), do: result_block(id, encode_delta(delta))

  defp encode_delta(delta) do
    json = Jason.encode!(delta)

    if byte_size(json) <= @tool_result_limit do
      json
    else
      String.slice(json, 0, @tool_result_limit) <>
        "… (truncated; #{map_size(delta)} state key(s) changed in full)"
    end
  end

  defp result_block(id, content) do
    %{"type" => "tool_result", "tool_use_id" => id, "content" => content}
  end

  defp error_result(id, reason) do
    id |> result_block(reason) |> Map.put("is_error", true)
  end

  # The model often narrates before calling a tool; surface it in the logs so
  # the run is followable without reading the raw conversation.
  defp log_text_blocks(ctx, content) do
    content
    |> Enum.filter(&(is_map(&1) and &1["type"] == "text"))
    |> Enum.map(&String.trim(&1["text"] || ""))
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&StepContext.info(ctx, "agent: #{String.slice(&1, 0, 500)}"))
  end

  # Persists usage on the step's metadata and accumulates the budget counter
  # in the shared state. Returns the (possibly updated) ctx plus a usage
  # summary for the log line, or nil when the response carried no usage.
  defp record_usage(ctx, model, %{"usage" => usage} = response, duration_ms)
       when is_map(usage) do
    input = usage["input_tokens"] || 0
    output = usage["output_tokens"] || 0
    cost = Pricing.estimate(model, input, output)

    # A tool-use run bills one API call per turn into this same row, so the
    # counters carry the run's totals rather than the last turn's — the
    # execution's cost display sums one number per step, and a multi-turn
    # agent would otherwise report a fraction of what it actually spent.
    # `stopReason` stays the latest: it describes how the run ended.
    prev = ctx.step_execution_id |> Executions.step_metadata() |> Map.get("agent", %{})

    meta =
      %{
        "model" => model,
        "inputTokens" => add(prev, "inputTokens", input),
        "outputTokens" => add(prev, "outputTokens", output),
        "turns" => add(prev, "turns", 1),
        "stopReason" => Map.get(response, "stop_reason"),
        "durationMs" => add(prev, "durationMs", duration_ms)
      }
      |> maybe_put(
        "cacheReadInputTokens",
        add(prev, "cacheReadInputTokens", usage["cache_read_input_tokens"])
      )
      |> maybe_put(
        "cacheCreationInputTokens",
        add(prev, "cacheCreationInputTokens", usage["cache_creation_input_tokens"])
      )
      |> maybe_put("estimatedCostUsd", add(prev, "estimatedCostUsd", cost))

    Executions.put_step_metadata!(ctx.step_execution_id, %{"agent" => meta})

    ctx = StepContext.put_state(ctx, @tokens_key, tokens_used(ctx) + input + output)
    {ctx, %{input: input, output: output, cost: cost}}
  end

  defp record_usage(ctx, _model, _response, _duration_ms), do: {ctx, nil}

  # Adds this turn's value to what previous turns already recorded. A value the
  # response omitted (an unpriced model, no cache tokens) leaves the running
  # total untouched instead of resetting it to nil.
  defp add(_prev, _key, nil), do: nil
  defp add(prev, key, value), do: (Map.get(prev, key) || 0) + value

  defp answered_line(model, nil), do: "agent: #{model} answered"

  defp answered_line(model, %{input: input, output: output, cost: nil}),
    do: "agent: #{model} answered (in=#{input} out=#{output} tokens)"

  defp answered_line(model, %{input: input, output: output, cost: cost}) do
    "agent: #{model} answered (in=#{input} out=#{output} tokens, ~$#{format_cost(cost)})"
  end

  defp format_cost(cost), do: :erlang.float_to_binary(cost * 1.0, decimals: 4)
end
