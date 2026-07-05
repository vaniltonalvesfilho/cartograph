defmodule CartographBackend.Executions.TaskExecution do
  use Ecto.Schema
  import Ecto.Changeset

  alias CartographBackend.Executions.Status

  schema "task_execution" do
    field :task_definition_id, :integer
    field :task_name, :string
    field :status, :string, default: Status.pending()
    field :trigger, :string, default: "manual"
    field :stop_requested, :boolean, default: false
    field :created_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
  end

  @doc """
  Builds a new execution. `trigger` records how it was started — "manual"
  (user-triggered) or "cron" (scheduled) — so manual and automatic runs share
  the same history while remaining distinguishable.
  """
  def new_changeset(task, trigger \\ "manual") do
    %__MODULE__{}
    |> change(%{
      task_definition_id: task.id,
      task_name: task.name,
      status: Status.pending(),
      trigger: trigger,
      stop_requested: false,
      created_at: DateTime.utc_now()
    })
  end

  def status_changeset(execution, status, extra \\ %{}) do
    execution
    |> change(Map.merge(%{status: status}, extra))
  end
end
