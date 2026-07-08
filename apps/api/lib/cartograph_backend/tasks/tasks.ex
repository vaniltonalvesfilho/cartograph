defmodule CartographBackend.Tasks do
  @moduledoc "Context for task definitions and triggering executions."

  import Ecto.Query
  alias CartographBackend.Repo
  alias CartographBackend.Tasks.TaskDefinition
  alias CartographBackend.Executions.TaskExecution
  alias CartographBackend.Dsl.{Parser, Expander}
  alias CartographBackend.Engine.CronScheduler

  # ── Queries ──────────────────────────────────────────────────────────────────

  def list_tasks(opts \\ []) do
    query = from t in TaskDefinition, order_by: [desc: t.created_at]

    query =
      if project_id = opts[:project_id] do
        where(query, [t], t.project_id == ^project_id)
      else
        query
      end

    Repo.all(query)
  end

  def get_task(id) do
    case Repo.get(TaskDefinition, id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  def available_steps, do: CartographBackend.Steps.Registry.available_steps()

  # ── Mutations ─────────────────────────────────────────────────────────────────

  # `actor` is the user authoring the change (or an explicit `:system` for
  # server-side flows like seeds). The DSL's `use` refs are validated against
  # the actor: each referenced job must exist AND be viewable by the actor, so
  # a job can't be chained into without access. No default on purpose — the
  # privileged :system bypass must always be a conscious choice.
  def create_task(attrs, actor) do
    dsl = Map.get(attrs, "dsl") || Map.get(attrs, :dsl, "")

    with :ok <- validate_dsl(dsl, actor) do
      result =
        %TaskDefinition{}
        |> TaskDefinition.changeset(attrs)
        |> Repo.insert()

      if match?({:ok, _}, result), do: maybe_reload_cron(attrs)
      result
    end
  end

  def update_task(id, attrs, actor) do
    with {:ok, task} <- get_task(id) do
      dsl = Map.get(attrs, "dsl") || Map.get(attrs, :dsl)

      with :ok <- validate_dsl_if_present(dsl, actor) do
        result =
          task
          |> TaskDefinition.update_changeset(attrs)
          |> Repo.update()

        if match?({:ok, _}, result), do: maybe_reload_cron(attrs)
        result
      end
    end
  end

  def delete_task(id) do
    case Repo.get(TaskDefinition, id) do
      nil ->
        {:error, :not_found}

      task ->
        result = Repo.delete(task)
        if match?({:ok, _}, result), do: CronScheduler.reload()
        result
    end
  end

  # Pre-flight expand runs as :system on purpose: refs were authorized against
  # the author at save time, and a run (manual or cron) executes the job as
  # published — the runner needs :run on this task (checked by the callers),
  # not :view on every referenced job.
  def run(task_id, trigger \\ "manual") do
    with {:ok, task} <- get_task(task_id),
         :ok <- check_released(task),
         :ok <- check_archived(task),
         {:ok, parsed} <- Parser.parse(task.dsl),
         {:ok, _} <- Expander.expand(parsed.steps, :system) do
      Repo.transaction(fn ->
        execution =
          task
          |> TaskExecution.new_changeset(trigger)
          |> Repo.insert!()

        {:ok, _job} =
          Oban.insert(CartographBackend.Engine.ExecutorWorker.new(%{execution_id: execution.id}))

        %{execution_id: execution.id}
      end)
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  # Blocks execution (manual or scheduled) before the release date. The cron
  # scheduler already defers automatic runs; this also guards manual runs and
  # any direct call to run/2.
  defp check_released(%{release_at: %DateTime{} = release_at}) do
    if DateTime.compare(release_at, DateTime.utc_now()) == :gt do
      {:error,
       "Job has not been released yet (available from #{Calendar.strftime(release_at, "%Y-%m-%d %H:%M UTC")})"}
    else
      :ok
    end
  end

  defp check_released(_), do: :ok

  # Blocks execution once the job is archived (at or after archive_at).
  defp check_archived(%{archive_at: %DateTime{} = archive_at}) do
    if DateTime.compare(DateTime.utc_now(), archive_at) != :lt do
      {:error,
       "Job arquivado (parado desde #{Calendar.strftime(archive_at, "%d/%m/%Y %H:%M UTC")})"}
    else
      :ok
    end
  end

  defp check_archived(_), do: :ok

  defp validate_dsl_if_present(nil, _actor), do: :ok
  defp validate_dsl_if_present(dsl, actor), do: validate_dsl(dsl, actor)

  # Parse + expand: surfaces both syntax errors and unresolvable/forbidden refs
  # as a binary error (turned into a 400 by the callers).
  defp validate_dsl(dsl, actor) do
    with {:ok, parsed} <- Parser.parse(dsl),
         {:ok, _} <- Expander.expand(parsed.steps, expand_ctx(actor)) do
      :ok
    end
  end

  defp expand_ctx(:system), do: :system
  defp expand_ctx(user), do: %{user: user}

  defp maybe_reload_cron(attrs) do
    if Map.has_key?(attrs, "cron") or Map.has_key?(attrs, :cron) do
      CronScheduler.reload()
    end
  end
end
