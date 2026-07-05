defmodule CartographBackend.Engine.ExecutorWorker do
  @moduledoc """
  Oban worker that runs a task execution. Loads the job, parses and expands its
  DSL, then hands the AST to `Engine.Interpreter` to walk. Persistence lives in
  the `Executions` context; this module only orchestrates the run and broadcasts
  status transitions to subscribers.
  """

  use Oban.Worker, queue: :executions, max_attempts: 1

  alias CartographBackend.Dsl.{Parser, Expander}
  alias CartographBackend.Engine.{LogBroadcaster, Interpreter}
  alias CartographBackend.Executions
  alias CartographBackend.Executions.Status
  alias CartographBackend.Tasks

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => execution_id}}) do
    execution = Executions.get_execution!(execution_id)
    {:ok, task_def} = Tasks.get_task(execution.task_definition_id)

    {:ok, parsed}   = Parser.parse(task_def.dsl)
    # :system — server-side execution runs the job as published; refs were
    # authorized against the author when the DSL was saved.
    {:ok, expanded} = Expander.expand(parsed.steps, :system)

    execution = Executions.start_execution!(execution)
    broadcast_status(execution)
    LogBroadcaster.log(execution_id, nil, "INFO", "Execution started")

    result =
      try do
        Interpreter.run(expanded, execution_id, task_def.project_id)
      rescue
        e ->
          msg = Exception.message(e)
          LogBroadcaster.log(execution_id, nil, "ERROR", "Execution crashed: #{msg}")
          {:error, msg}
      end

    final_status =
      case result do
        {:ok, _, _}      -> Status.success()
        {:stopped, _, _} -> Status.stopped()
        {:error, _}      -> Status.failed()
      end

    done = Executions.finish_execution!(execution_id, final_status)

    if final_status == Status.failed() do
      CartographBackend.Mailing.notify_execution_failure_async(done, task_def.project_id)
    end

    broadcast_status(done)
    LogBroadcaster.log(execution_id, nil, "INFO", "Execution finished: #{final_status}")
    LogBroadcaster.complete(execution_id)

    :ok
  end

  # Notify status subscribers (REST via PubSub, GraphQL via Absinthe).
  defp broadcast_status(execution) do
    Phoenix.PubSub.broadcast(
      CartographBackend.PubSub,
      "execution_status:#{execution.id}",
      {:status, execution}
    )

    Absinthe.Subscription.publish(
      CartographBackendWeb.Endpoint,
      execution,
      execution_status: "execution_status:#{execution.id}",
      task_execution_updated: "task_executions:#{execution.task_definition_id}"
    )
  end
end
