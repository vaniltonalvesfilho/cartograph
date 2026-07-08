defmodule CartographBackend.Executions.StepExecution do
  use Ecto.Schema
  import Ecto.Changeset

  alias CartographBackend.Executions.Status

  schema "step_execution" do
    field :execution_id, :integer
    field :step_name, :string
    field :step_order, :integer
    field :status, :string, default: Status.pending()
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :error_message, :string
    field :flow_node_id, :string
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [
      :execution_id,
      :step_name,
      :step_order,
      :status,
      :started_at,
      :finished_at,
      :error_message,
      :flow_node_id
    ])
    |> validate_required([:execution_id, :step_name, :step_order])
  end

  def status_changeset(step, status, extra \\ %{}) do
    step
    |> change(Map.merge(%{status: status}, extra))
  end
end
