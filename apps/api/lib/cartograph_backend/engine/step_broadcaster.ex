defmodule CartographBackend.Engine.StepBroadcaster do
  @moduledoc """
  Pushes a `step_execution` row to live subscribers so a UI can paint the flow
  graph without polling.

  Two channels, on purpose: Phoenix.PubSub for REST/SSE consumers, Absinthe for
  the GraphQL `step_updated` subscription. Both the Interpreter (top-level
  steps) and the agent step (its tool calls) publish through here, so a tool
  call shows up live exactly like any other step.
  """

  @doc "Broadcasts `step` on both channels. Returns the step for pipelining."
  def broadcast(step) do
    Phoenix.PubSub.broadcast(
      CartographBackend.PubSub,
      "execution_steps:#{step.execution_id}",
      {:step, step}
    )

    Absinthe.Subscription.publish(
      CartographBackendWeb.Endpoint,
      step,
      step_updated: "execution_steps:#{step.execution_id}"
    )

    step
  end
end
