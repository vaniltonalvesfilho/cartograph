defmodule CartographBackend.Repo.Migrations.AddParentToStepExecution do
  use Ecto.Migration

  def change do
    alter table(:step_execution) do
      # Set when a step was invoked as a tool by an agent step (AI Agent Jobs
      # phase 2). Nullable: every ordinary step the interpreter runs stays
      # top-level with nil here. Deleting the parent removes its tool calls —
      # a tool call has no meaning without the agent turn that made it.
      add :parent_step_execution_id,
          references(:step_execution, on_delete: :delete_all)
    end

    create index(:step_execution, [:parent_step_execution_id])
  end
end
