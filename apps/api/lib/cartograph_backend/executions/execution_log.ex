defmodule CartographBackend.Executions.ExecutionLog do
  use Ecto.Schema

  schema "execution_log" do
    field :execution_id, :integer
    field :step_execution_id, :integer
    field :level, :string
    field :message, :string
    field :timestamp, :utc_datetime_usec
  end
end
