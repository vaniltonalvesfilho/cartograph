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
    CartographBackend.Steps.NotifyStep
  ]

  @by_name Map.new(@steps, fn mod -> {mod.name(), mod} end)

  @doc "Returns the module for the given step name, or an error tuple."
  @spec get(String.t()) :: {:ok, module()} | {:error, String.t()}
  def get(name) do
    case Map.fetch(@by_name, name) do
      {:ok, mod} ->
        {:ok, mod}

      :error ->
        {:error,
         "Unknown step '#{name}'. Available: #{available_steps() |> Enum.join(", ")}"}
    end
  end

  @doc "Returns all registered step names, sorted alphabetically."
  @spec available_steps() :: [String.t()]
  def available_steps, do: @by_name |> Map.keys() |> Enum.sort()
end
