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
  """
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Agents
  alias CartographBackend.Agents.{AnthropicClient, Pricing}
  alias CartographBackend.Engine.StepContext
  alias CartographBackend.{Executions, Vault}

  @default_model "claude-opus-4-8"
  @default_output "agent_result"
  @default_max_tokens 4096
  # We do not stream in phase 1; larger values risk HTTP timeouts.
  @max_tokens_cap 16_000

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
        body = build_body(params, max_tokens, system, rendered_prompt)
        call_api(ctx, credential, body)
      end
    else
      {:secret, false} ->
        {:error,
         "agent: 'secret' param is required (the Anthropic credential code, e.g. anthropic-uI0IOQ45)"}

      {:prompt, false} ->
        {:error, "agent: 'prompt' param is required"}

      {:max_tokens, {:error, reason}} ->
        {:error, reason}

      {:credential, {:error, _}} ->
        {:error, not_accessible(code)}

      {:render, {:error, reason}} ->
        {:error, reason}

      {:budget, {:error, reason}} ->
        {:error, reason}
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

  defp build_body(params, max_tokens, system, prompt) do
    %{
      "model" => model(params),
      "max_tokens" => max_tokens,
      "messages" => [%{"role" => "user", "content" => prompt}]
    }
    |> maybe_put("system", system)
    |> maybe_put("temperature", numeric_param(params, "temperature"))
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

  defp tokens_used(ctx), do: StepContext.get_state(ctx, @tokens_key, 0)

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
        # that carries it — max_tokens/refusal tokens were billed too.
        {ctx, usage} = record_usage(ctx, body["model"], response, duration_ms)
        handle_response(ctx, response, usage, body)
    end
  end

  defp handle_response(ctx, %{"stop_reason" => "end_turn"} = response, usage, body) do
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
  defp handle_response(_ctx, %{"stop_reason" => "max_tokens"}, _usage, body) do
    {:error,
     "agent: response truncated at maxTokens=#{body["max_tokens"]}; raise maxTokens or shorten the prompt"}
  end

  defp handle_response(_ctx, %{"stop_reason" => "refusal"}, _usage, _body) do
    {:error, "agent: the model declined this request (refusal)"}
  end

  defp handle_response(_ctx, response, _usage, _body) do
    {:error, "agent: unexpected stop_reason '#{Map.get(response, "stop_reason")}'"}
  end

  # Persists usage on the step's metadata and accumulates the budget counter
  # in the shared state. Returns the (possibly updated) ctx plus a usage
  # summary for the log line, or nil when the response carried no usage.
  defp record_usage(ctx, model, %{"usage" => usage} = response, duration_ms)
       when is_map(usage) do
    input = usage["input_tokens"] || 0
    output = usage["output_tokens"] || 0
    cost = Pricing.estimate(model, input, output)

    meta =
      %{
        "model" => model,
        "inputTokens" => input,
        "outputTokens" => output,
        "stopReason" => Map.get(response, "stop_reason"),
        "durationMs" => duration_ms
      }
      |> maybe_put("cacheReadInputTokens", usage["cache_read_input_tokens"])
      |> maybe_put("cacheCreationInputTokens", usage["cache_creation_input_tokens"])
      |> maybe_put("estimatedCostUsd", cost)

    Executions.put_step_metadata!(ctx.step_execution_id, %{"agent" => meta})

    ctx = StepContext.put_state(ctx, @tokens_key, tokens_used(ctx) + input + output)
    {ctx, %{input: input, output: output, cost: cost}}
  end

  defp record_usage(ctx, _model, _response, _duration_ms), do: {ctx, nil}

  defp answered_line(model, nil), do: "agent: #{model} answered"

  defp answered_line(model, %{input: input, output: output, cost: nil}),
    do: "agent: #{model} answered (in=#{input} out=#{output} tokens)"

  defp answered_line(model, %{input: input, output: output, cost: cost}) do
    "agent: #{model} answered (in=#{input} out=#{output} tokens, ~$#{format_cost(cost)})"
  end

  defp format_cost(cost), do: :erlang.float_to_binary(cost * 1.0, decimals: 4)
end
