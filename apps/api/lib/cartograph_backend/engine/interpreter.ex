defmodule CartographBackend.Engine.Interpreter do
  @moduledoc """
  Walks an expanded DSL AST for a running execution: reduces steps in order,
  descends into the taken branch of each `IfNode`, and runs each step through its
  registered module against the shared state.

  Persistence (step records, status transitions, cancellation checks) goes through
  the `Executions` context; the actual work of a step is delegated to the module
  the `Steps.Registry` resolves for its name. Returns:

      {:ok, state, order} | {:stopped, state, order} | {:error, reason}
  """

  alias CartographBackend.Dsl.{Condition, IfNode}
  alias CartographBackend.Engine.{LogBroadcaster, StepContext}
  alias CartographBackend.Executions
  alias CartographBackend.Executions.Status
  alias CartographBackend.Steps.Registry

  @doc "Runs the expanded `nodes` for `execution_id` from empty state / order 0."
  def run(nodes, execution_id, project_id) do
    walk_nodes(nodes, execution_id, %{}, 0, project_id)
  end

  # ── Tree walker ──────────────────────────────────────────────────────────────

  defp walk_nodes(nodes, execution_id, state, order, project_id) do
    Enum.reduce_while(nodes, {:ok, state, order}, fn node, {:ok, cur_state, cur_order} ->
      case walk_node(node, execution_id, cur_state, cur_order, project_id) do
        {:ok, new_state, new_order} -> {:cont, {:ok, new_state, new_order}}
        {:stopped, new_state, new_order} -> {:halt, {:stopped, new_state, new_order}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp walk_node(%IfNode{} = node, execution_id, state, order, project_id) do
    branch =
      if Condition.eval(node.condition, state),
        do: node.then_steps,
        else: node.else_steps

    LogBroadcaster.log(
      execution_id,
      nil,
      "INFO",
      "Branch taken: #{if Condition.eval(node.condition, state), do: "then", else: "else"}"
    )

    walk_nodes(branch, execution_id, state, order, project_id)
  end

  defp walk_node(spec, execution_id, state, order, project_id) do
    new_order = order + 1

    if Executions.stop_requested?(execution_id) do
      {:stopped, state, new_order}
    else
      step = Executions.create_step!(execution_id, spec.name, new_order, spec.flow_id)
      broadcast_step(step)
      run_one_step(execution_id, step, spec, state, new_order, project_id)
    end
  end

  # ── Step execution ───────────────────────────────────────────────────────────

  defp run_one_step(execution_id, step, spec, state, order, project_id) do
    # Rebind so later transitions (and their broadcasts) carry started_at.
    step = set_step_status(step, Status.running())
    LogBroadcaster.log(execution_id, step.id, "INFO", "Step '#{step.step_name}' started")

    ctx = %StepContext{
      params: spec.params,
      state: state,
      execution_id: execution_id,
      step_execution_id: step.id,
      project_id: project_id,
      log: fn level, msg -> LogBroadcaster.log(execution_id, step.id, level, msg) end,
      cancelled?: fn -> Executions.stop_requested?(execution_id) end
    }

    case Registry.get(spec.name) do
      {:error, reason} ->
        set_step_status(step, Status.failed(), reason)
        LogBroadcaster.log(execution_id, step.id, "ERROR", reason)
        {:error, reason}

      {:ok, module} ->
        case module.execute(ctx) do
          {:ok, new_ctx} ->
            if Executions.stop_requested?(execution_id) do
              set_step_status(step, Status.stopped())
              {:stopped, new_ctx.state, order}
            else
              set_step_status(step, Status.success())

              LogBroadcaster.log(
                execution_id,
                step.id,
                "INFO",
                "Step '#{step.step_name}' finished"
              )

              {:ok, new_ctx.state, order}
            end

          {:error, reason} ->
            set_step_status(step, Status.failed(), reason)

            LogBroadcaster.log(
              execution_id,
              step.id,
              "ERROR",
              "Step '#{step.step_name}' failed: #{reason}"
            )

            {:error, reason}
        end
    end
  end

  # ── Step broadcast ───────────────────────────────────────────────────────────

  # Persists the status transition and pushes the fresh step to subscribers, so
  # a UI can paint the flow graph live without polling (see graph viz plan).
  defp set_step_status(step, status, error \\ nil) do
    updated = Executions.update_step_status!(step, status, error)
    broadcast_step(updated)
    updated
  end

  # Same dual channel as ExecutorWorker.broadcast_status: PubSub for REST/SSE
  # consumers, Absinthe for the GraphQL `step_updated` subscription.
  defp broadcast_step(step) do
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
  end
end
