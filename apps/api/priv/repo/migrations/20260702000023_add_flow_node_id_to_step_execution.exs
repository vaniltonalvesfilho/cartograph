defmodule CartographBackend.Repo.Migrations.AddFlowNodeIdToStepExecution do
  use Ecto.Migration

  def change do
    alter table(:step_execution) do
      # Structural path of the flow node that produced this step (see Dsl.Flow),
      # e.g. "0", "1/t0", "2/j0". Nullable: rows from before this migration and
      # steps whose provenance is unknown simply have no overlay in the UI.
      add :flow_node_id, :string
    end
  end
end
