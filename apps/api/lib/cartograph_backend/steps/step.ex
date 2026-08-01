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

  @doc """
  Anthropic tool definition, exposing this step to agent steps as a callable
  tool (AI Agent Jobs phase 2).

  **Implementing this is a security decision, not a formality.** A tool's
  params are written by a language model, so they must be validated exactly as
  if they arrived from an unauthenticated request — and because steps talk to
  each other through the shared state, a tool call mutates the state that
  later, non-agent steps will read. Only steps that are read-only or pure
  belong here; see `docs/design/ai-agent-tool-use.md`.

  Not implementing it is the default, and it means the step can never be
  reached by an agent.

  `description` is written *for the model*: say when to reach for the tool,
  not just what it does.
  """
  @callback tool_schema() :: %{description: String.t(), input_schema: map()}

  @optional_callbacks tool_schema: 0
end
