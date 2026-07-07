defmodule CartographBackend.Engine.CronScheduler do
  @moduledoc """
  GenServer that schedules recurring task executions based on cron expressions.
  Uses Process.send_after for true cron semantics (fires at exact calendar times).
  In a multi-node cluster, every node runs this scheduler — idempotency relies
  on Oban's job deduplication. Distributed cron deduplication is a future concern.
  """

  use GenServer
  require Logger

  alias CartographBackend.Repo
  alias CartographBackend.Tasks.TaskDefinition

  import Ecto.Query

  @name __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: @name)

  @doc "Reload all cron schedules from the database (call after create/update/delete task)."
  @spec reload() :: :ok
  def reload, do: GenServer.cast(@name, :reload)

  # ── Callbacks ────────────────────────────────────────────────────────────────

  @impl true
  def init(_) do
    state = %{timers: %{}}
    {:ok, state, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, state) do
    {:noreply, load_all(state)}
  end

  @impl true
  def handle_cast(:reload, state) do
    state = cancel_all(state)
    {:noreply, load_all(state)}
  end

  @impl true
  def handle_info({:tick, task_id}, state) do
    case schedule_next(task_id) do
      {:ok, timer_ref} ->
        Task.start(fn -> CartographBackend.Tasks.run(task_id, "cron") end)
        {:noreply, put_in(state, [:timers, task_id], timer_ref)}

      :skip ->
        {:noreply, Map.update!(state, :timers, &Map.delete(&1, task_id))}
    end
  end

  # ── Internals ─────────────────────────────────────────────────────────────────

  defp load_all(state) do
    tasks =
      Repo.all(
        from t in TaskDefinition,
          where: not is_nil(t.cron) and t.cron != "",
          select: {t.id, t.cron, t.release_at, t.archive_at}
      )

    timers =
      Enum.reduce(tasks, %{}, fn {id, cron, release_at, archive_at}, acc ->
        case schedule_next(id, cron, release_at, archive_at) do
          {:ok, ref} -> Map.put(acc, id, ref)
          :skip -> acc
        end
      end)

    %{state | timers: timers}
  end

  defp cancel_all(%{timers: timers} = state) do
    Enum.each(timers, fn {_id, ref} -> Process.cancel_timer(ref) end)
    %{state | timers: %{}}
  end

  defp schedule_next(task_id) do
    case Repo.get(TaskDefinition, task_id) do
      %{cron: cron, release_at: release_at, archive_at: archive_at}
      when is_binary(cron) and cron != "" ->
        schedule_next(task_id, cron, release_at, archive_at)

      _ ->
        :skip
    end
  end

  defp schedule_next(task_id, cron_expr, release_at, archive_at) do
    with {:ok, expr} <- Crontab.CronExpression.Parser.parse(cron_expr),
         {:ok, next} <- Crontab.Scheduler.get_next_run_date(expr, from_time(release_at)) do
      if past_archive?(next, archive_at) do
        # Next occurrence falls at/after the archive date — job is archived, stop scheduling.
        :skip
      else
        delay = max(DateTime.diff(next, DateTime.utc_now(), :millisecond), 0)
        ref = Process.send_after(self(), {:tick, task_id}, delay)
        {:ok, ref}
      end
    else
      {:error, reason} ->
        Logger.warning(
          "CronScheduler: invalid cron '#{cron_expr}' for task #{task_id}: #{reason}"
        )

        :skip
    end
  end

  # True when the next run lands at or after the archive date.
  defp past_archive?(next, %DateTime{} = archive_at),
    do: DateTime.compare(next, archive_at) != :lt

  defp past_archive?(_next, _), do: false

  # Reference instant for the next-run search: the later of "now" and the
  # release date. Before the release date, the first scheduled run is the first
  # cron occurrence at or after it; with no release date, behaves as before.
  defp from_time(%DateTime{} = release_at) do
    now = DateTime.utc_now()
    if DateTime.compare(release_at, now) == :gt, do: release_at, else: now
  end

  defp from_time(_), do: DateTime.utc_now()
end
