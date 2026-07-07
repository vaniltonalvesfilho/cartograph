defmodule CartographBackend.Metrics do
  import Ecto.Query
  alias CartographBackend.Repo
  alias CartographBackend.Tasks.TaskDefinition
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Executions.TaskExecution
  alias CartographBackend.Executions.Status

  def dashboard_metrics do
    total_tasks = Repo.aggregate(TaskDefinition, :count)
    total_groups = Repo.aggregate(Group, :count)
    total_projects = Repo.aggregate(Project, :count)
    scheduled = Repo.aggregate(from(t in TaskDefinition, where: not is_nil(t.cron)), :count)

    running =
      Repo.aggregate(from(e in TaskExecution, where: e.status in ^Status.active()), :count)

    statuses =
      Repo.all(
        from e in TaskExecution,
          where: e.status in ^Status.terminal(),
          select: e.status
      )

    total_terminal = length(statuses)
    successes = Enum.count(statuses, &(&1 == Status.success()))

    success_rate =
      if total_terminal > 0, do: Float.round(successes / total_terminal * 100, 1), else: nil

    %{
      total_tasks: total_tasks,
      total_groups: total_groups,
      total_projects: total_projects,
      running: running,
      scheduled: scheduled,
      success_rate: success_rate
    }
  end
end
