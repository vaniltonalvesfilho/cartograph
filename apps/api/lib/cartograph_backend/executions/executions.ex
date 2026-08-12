defmodule CartographBackend.Executions do
  @moduledoc "Context for querying and controlling task executions."

  import Ecto.Query
  alias CartographBackend.Repo
  alias CartographBackend.Executions.{TaskExecution, StepExecution, ExecutionLog, Status}

  # ── Queries ──────────────────────────────────────────────────────────────────

  def list_executions(opts \\ []) do
    query = from e in TaskExecution, order_by: [desc: e.created_at]

    query =
      if task_id = opts[:task_id] do
        where(query, [e], e.task_definition_id == ^task_id)
      else
        query
      end

    Repo.all(query)
  end

  def get_execution(id) do
    case Repo.get(TaskExecution, id) do
      nil ->
        {:error, :not_found}

      execution ->
        steps =
          Repo.all(
            from s in StepExecution,
              where: s.execution_id == ^id,
              # `step_order` is scoped to the parent for tool calls, so a child
              # ties with the top-level steps 1, 2, 3… Ordering by id as well
              # keeps the flat list stable and chronological instead of
              # leaving the tie to the database.
              order_by: [asc: s.step_order, asc: s.id]
          )

        {:ok, %{execution: execution, steps: steps}}
    end
  end

  def list_logs(execution_id) do
    Repo.all(
      from l in ExecutionLog,
        where: l.execution_id == ^execution_id,
        order_by: [asc: l.id]
    )
  end

  # ── Mutations ─────────────────────────────────────────────────────────────────

  def stop(execution_id) do
    case Repo.get(TaskExecution, execution_id) do
      nil ->
        {:error, :not_found}

      execution ->
        if Status.active?(execution.status) do
          execution
          |> Ecto.Changeset.change(stop_requested: true)
          |> Repo.update()
        else
          {:error, :not_running}
        end
    end
  end

  # ── Engine lifecycle (persistence for the runtime; see Engine.Interpreter) ────

  @doc "Fetches an execution by id, raising if it does not exist."
  def get_execution!(id), do: Repo.get!(TaskExecution, id)

  @doc "Marks an execution as running and stamps `started_at`."
  def start_execution!(%TaskExecution{} = execution) do
    execution
    |> TaskExecution.status_changeset(Status.running(), %{started_at: DateTime.utc_now()})
    |> Repo.update!()
  end

  @doc "Marks an execution finished with `status` and stamps `finished_at`."
  def finish_execution!(id, status) do
    Repo.get!(TaskExecution, id)
    |> TaskExecution.status_changeset(status, %{finished_at: DateTime.utc_now()})
    |> Repo.update!()
  end

  @doc "True if a stop was requested for the execution (cooperative cancellation)."
  def stop_requested?(id) do
    Repo.one(from e in TaskExecution, where: e.id == ^id, select: e.stop_requested) == true
  end

  @doc """
  Creates a pending step record just-in-time as the interpreter reaches it.
  `flow_node_id` is the Dsl.Flow structural id of the node that produced the
  step (nil when provenance is unknown).
  """
  def create_step!(execution_id, name, order, flow_node_id \\ nil) do
    %StepExecution{}
    |> StepExecution.changeset(%{
      execution_id: execution_id,
      step_name: name,
      step_order: order,
      status: Status.pending(),
      flow_node_id: flow_node_id
    })
    |> Repo.insert!()
  end

  @doc """
  Creates a pending step record for a step invoked as a *tool* by an agent
  step. `order` is scoped to the parent (its tool calls number 1, 2, 3… in
  call order), so children never disturb the interpreter's top-level sequence.

  There is no `flow_node_id`: a tool call has no node in the authored DSL —
  the model decided to make it at runtime.
  """
  def create_child_step!(execution_id, name, order, parent_step_execution_id) do
    %StepExecution{}
    |> StepExecution.changeset(%{
      execution_id: execution_id,
      step_name: name,
      step_order: order,
      status: Status.pending(),
      parent_step_execution_id: parent_step_execution_id
    })
    |> Repo.insert!()
  end

  @doc """
  Reads a step's `metadata` jsonb, defaulting to an empty map. Lets a step that
  writes metadata more than once per run accumulate onto what it already wrote
  (the agent step bills every turn of a tool-use loop into the same row).
  """
  def step_metadata(step_execution_id) do
    Repo.get!(StepExecution, step_execution_id).metadata || %{}
  end

  @doc """
  Deep-merges `map` into the step's `metadata` jsonb column. Used by steps to
  record telemetry mid-run (e.g. the agent step's token usage); each step type
  owns its own top-level key so merges never clobber a sibling's data.
  """
  def put_step_metadata!(step_execution_id, map) when is_map(map) do
    step = Repo.get!(StepExecution, step_execution_id)

    step
    |> Ecto.Changeset.change(metadata: deep_merge(step.metadata || %{}, map))
    |> Repo.update!()
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, l, r ->
      if is_map(l) and is_map(r), do: deep_merge(l, r), else: r
    end)
  end

  @doc """
  Updates a step's status, stamping `started_at`/`finished_at` from the status and
  recording `error` (when given) on the step.
  """
  def update_step_status!(step, status, error \\ nil) do
    # Re-read the row first: the step may have written `metadata` mid-run (see
    # put_step_metadata!/2) and the interpreter's in-memory struct is stale —
    # the final status broadcast must carry that metadata to live subscribers.
    step = Repo.get!(StepExecution, step.id)
    now = DateTime.utc_now()

    time_fields =
      cond do
        status == Status.running() -> %{started_at: now}
        Status.terminal?(status) -> %{finished_at: now}
        true -> %{}
      end

    extra = if error, do: Map.put(time_fields, :error_message, error), else: time_fields

    step
    |> StepExecution.status_changeset(status, extra)
    |> Repo.update!()
  end
end
