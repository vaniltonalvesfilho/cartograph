defmodule CartographBackend.DataSources.DataSourceProject do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "data_source_projects" do
    belongs_to :data_source, CartographBackend.DataSources.DataSource
    belongs_to :project, CartographBackend.Groups.Project
    timestamps()
  end

  def changeset(dsp, attrs) do
    dsp
    |> cast(attrs, [:data_source_id, :project_id])
    |> validate_required([:data_source_id, :project_id])
    |> unique_constraint([:data_source_id, :project_id],
      name: :data_source_projects_data_source_id_project_id_index
    )
  end
end
