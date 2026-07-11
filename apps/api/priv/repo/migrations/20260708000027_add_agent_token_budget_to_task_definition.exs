defmodule CartographBackend.Repo.Migrations.AddAgentTokenBudgetToTaskDefinition do
  use Ecto.Migration

  def change do
    alter table(:task_definition) do
      # Cumulative token cap (input + output) for all agent steps of one
      # execution of this job. NULL falls back to the server default
      # (:agent_token_budget_default, 200k).
      add :agent_token_budget, :integer
    end
  end
end
