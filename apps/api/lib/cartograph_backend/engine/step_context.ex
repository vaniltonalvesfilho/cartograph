defmodule CartographBackend.Engine.StepContext do
  @moduledoc """
  Carries all runtime data a step needs: params, shared state between steps,
  logging function, and a cancellation check function.
  """

  @type t :: %__MODULE__{
          params: map(),
          state: map(),
          execution_id: integer(),
          step_execution_id: integer(),
          project_id: integer() | nil,
          agent_token_budget: pos_integer() | nil,
          log: (String.t(), String.t() -> :ok),
          cancelled?: (-> boolean())
        }

  defstruct [
    :params,
    :state,
    :execution_id,
    :step_execution_id,
    :project_id,
    # Root job's agent token budget; nil means the server default applies.
    :agent_token_budget,
    :log,
    :cancelled?
  ]

  @doc "Log an INFO message via the injected logging function."
  def info(%__MODULE__{log: log_fn}, message), do: log_fn.("INFO", message)

  @doc "Log an ERROR message via the injected logging function."
  def error(%__MODULE__{log: log_fn}, message), do: log_fn.("ERROR", message)

  @doc "Returns true if the execution has been requested to stop."
  def cancelled?(%__MODULE__{cancelled?: check_fn}), do: check_fn.()

  @doc "Reads a value from the shared state map."
  def get_state(%__MODULE__{state: state}, key, default \\ nil) do
    Map.get(state, key, default)
  end

  @doc "Returns a new context with the updated shared state."
  def put_state(%__MODULE__{state: state} = ctx, key, value) do
    %{ctx | state: Map.put(state, key, value)}
  end
end
