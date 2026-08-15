defmodule CartographBackend.Engine.Provenance do
  @moduledoc """
  Tracks which shared-state keys were written by an agent's tool calls, so the
  steps that act on the outside world can refuse model-chosen data unless the
  job author opted in.

  ## Why

  Steps talk to each other through the shared state, and `parseJson`/`parseXml`
  take a model-chosen `result_key`. A tool-enabled agent can therefore write
  *any* state key — including the one a later `writeJson` or `executeDatabase`
  reads. The agent cannot **call** a dangerous step (the allowlist in
  `AgentStep` sees to that), but without this module it can still steer what a
  dangerous step later writes to disk or to the database.

  Naming the source key in an explicit param does not fix this: the key is
  still writable, it is only harder to guess. What fixes it is recording *who*
  wrote a value and making the sink decide, which is what happens here.

  ## The rule

  Every key a successful tool call added or changed is recorded under the
  reserved key `__agent_written__`. `writeOutput`, `writeJson`, `writeXml` and
  `executeDatabase` call `guard_consumption/3` on the key they are about to
  read and fail unless the author wrote `allowAgentData true` on that step.

  The mark is cleared when a later ordinary step overwrites the same key
  (`reconcile/2`): the value is author-controlled again, and a mark that never
  cleared would teach authors to set `allowAgentData true` everywhere.

  The whole `__` prefix is reserved for engine bookkeeping and tools may never
  write into it (`guard_reserved/2`) — the previous per-key guard on the token
  counter was a patch on one key rather than a rule.
  """

  alias CartographBackend.Engine.StepContext

  @agent_written_key "__agent_written__"
  @reserved_prefix "__"

  @doc "The reserved state key holding the list of agent-written key names."
  def agent_written_key, do: @agent_written_key

  @doc """
  True for keys in the engine's reserved namespace. Reserved keys are never
  shown to a model, never writable by a tool, and never treated as data.
  """
  def reserved?(key) when is_binary(key), do: String.starts_with?(key, @reserved_prefix)
  def reserved?(_key), do: false

  @doc """
  Returns `after_state` with every reserved key restored from `before`.

  A tool's params come from the model, so a tool call could otherwise reset the
  token budget counter or forge its own provenance record. Reserved keys the
  tool invented are dropped; reserved keys it overwrote are restored.
  """
  def guard_reserved(before, after_state) do
    kept = Map.reject(after_state, fn {key, _value} -> reserved?(key) end)
    reserved = Map.filter(before, fn {key, _value} -> reserved?(key) end)
    Map.merge(kept, reserved)
  end

  @doc "Records `keys` as written by an agent tool call."
  def mark_agent_written(state, keys) do
    keys = keys |> List.wrap() |> Enum.reject(&reserved?/1)

    case Enum.uniq(agent_written(state) ++ keys) do
      [] -> Map.delete(state, @agent_written_key)
      marked -> Map.put(state, @agent_written_key, Enum.sort(marked))
    end
  end

  @doc "Drops the agent mark from `keys` — their value is author-controlled again."
  def clear_agent_written(state, keys) do
    keys = List.wrap(keys)

    case agent_written(state) -- keys do
      [] -> Map.delete(state, @agent_written_key)
      marked -> Map.put(state, @agent_written_key, marked)
    end
  end

  @doc "The state keys currently marked as agent-written."
  def agent_written(state) do
    case Map.get(state, @agent_written_key) do
      list when is_list(list) -> Enum.filter(list, &is_binary/1)
      # Defensive: the key lives in the shared state, so a `use`-chained job
      # from before this feature — or a corrupt row — could carry anything.
      _ -> []
    end
  end

  @doc "True if `key` currently holds a value an agent's tool call produced."
  def agent_written?(state, key), do: key in agent_written(state)

  @doc """
  Settles provenance after an ordinary step ran, given the state before and
  after it.

  Keys the step rewrote lose their mark, *except* the ones the step itself
  marked — that exception is what lets `AgentStep` mark its own tool writes
  without the interpreter immediately undoing them.
  """
  def reconcile(before_state, after_state) do
    marked_by_step = agent_written(after_state) -- agent_written(before_state)

    rewritten =
      after_state
      |> Enum.filter(fn {key, value} ->
        not reserved?(key) and Map.get(before_state, key) != value
      end)
      |> Enum.map(fn {key, _value} -> key end)

    clear_agent_written(after_state, rewritten -- marked_by_step)
  end

  @doc """
  Fails a step that is about to consume agent-written data without the author
  saying so. `keys` may be a single key or a list; `nil` entries are ignored so
  callers can pass an optional param straight through.

  The opt-in is per step and per run, not global: writing `allowAgentData true`
  is the author stating that this particular sink is meant to act on whatever
  the model produced.
  """
  def guard_consumption(%StepContext{params: params, state: state}, keys, step_name) do
    keys = keys |> List.wrap() |> Enum.filter(&is_binary/1)

    if allow_agent_data?(params) do
      :ok
    else
      case Enum.filter(keys, &agent_written?(state, &1)) do
        [] ->
          :ok

        [key | _] ->
          {:error,
           "#{step_name}: state key '#{key}' was written by an agent tool call; " <>
             "set allowAgentData true to consume it deliberately"}
      end
    end
  end

  # The DSL parses a bare `true` into a boolean; the canvas stores params as
  # free-form strings, so the string form has to count too.
  defp allow_agent_data?(params) do
    case Map.get(params, "allowAgentData") do
      true -> true
      "true" -> true
      _ -> false
    end
  end
end
