defmodule CartographBackend.Steps.Step do
  @moduledoc """
  Behaviour for a Cartograph step.
  Implement this to add new capabilities (send email, run SQL, etc.) and
  register the module in CartographBackend.Steps.Registry.
  """

  alias CartographBackend.Engine.StepContext

  @doc "The DSL identifier for this step, e.g. \"readDirectory\"."
  @callback name() :: String.t()

  @doc "Executes the step. Returns {:ok, updated_ctx} or {:error, reason}."
  @callback execute(StepContext.t()) ::
              {:ok, StepContext.t()} | {:error, String.t()}
end
