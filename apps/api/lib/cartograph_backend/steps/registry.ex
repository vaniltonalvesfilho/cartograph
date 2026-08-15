defmodule CartographBackend.Steps.Registry do
  @moduledoc """
  Compile-time registry of all available steps.
  To add a new step, implement the Step behaviour and add the module to @steps.
  """

  @steps [
    CartographBackend.Steps.DelayStep,
    CartographBackend.Steps.ReadDirectoryStep,
    CartographBackend.Steps.FilterFilesStep,
    CartographBackend.Steps.TransformStep,
    CartographBackend.Steps.ValidateStep,
    CartographBackend.Steps.WriteOutputStep,
    CartographBackend.Steps.QueryDatabaseStep,
    CartographBackend.Steps.ExecuteDatabaseStep,
    CartographBackend.Steps.ParseXmlStep,
    CartographBackend.Steps.WriteXmlStep,
    CartographBackend.Steps.ParseJsonStep,
    CartographBackend.Steps.WriteJsonStep,
    CartographBackend.Steps.NotifyStep,
    CartographBackend.Steps.AgentStep
  ]

  @by_name Map.new(@steps, fn mod -> {mod.name(), mod} end)

  # Steps that opted in to being callable by an agent step, by declaring
  # `tool_schema/0`. Derived, never hand-listed: the opt-in lives next to the
  # step's own param validation, where the security decision belongs. A test
  # pins this set so a new step can't silently widen an agent's reach.
  @tool_capable @steps
                |> Enum.filter(fn mod ->
                  Code.ensure_compiled!(mod)
                  function_exported?(mod, :tool_schema, 0)
                end)
                |> Map.new(fn mod -> {mod.name(), mod} end)

  @doc "Returns the module for the given step name, or an error tuple."
  @spec get(String.t()) :: {:ok, module()} | {:error, String.t()}
  def get(name) do
    case Map.fetch(@by_name, name) do
      {:ok, mod} ->
        {:ok, mod}

      :error ->
        {:error, "Unknown step '#{name}'. Available: #{available_steps() |> Enum.join(", ")}"}
    end
  end

  @doc "Returns all registered step names, sorted alphabetically."
  @spec available_steps() :: [String.t()]
  def available_steps, do: @by_name |> Map.keys() |> Enum.sort()

  @doc """
  Names of the steps that may be exposed to an agent step as tools, sorted.

  This is only the first of two gates: a job author must still allowlist the
  step explicitly via the agent step's `tools` param.
  """
  @spec tool_capable() :: [String.t()]
  def tool_capable, do: @tool_capable |> Map.keys() |> Enum.sort()

  @doc "Returns the Anthropic tool definition for an agent-callable step."
  @spec tool_schema(String.t()) :: {:ok, map()} | {:error, String.t()}
  def tool_schema(name) do
    case Map.fetch(@tool_capable, name) do
      {:ok, mod} ->
        {:ok, mod.tool_schema()}

      :error ->
        {:error,
         "Step '#{name}' is not available to agents. Available: #{tool_capable() |> Enum.join(", ")}"}
    end
  end
end
