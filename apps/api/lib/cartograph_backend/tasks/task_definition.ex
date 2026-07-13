defmodule CartographBackend.Tasks.TaskDefinition do
  use Ecto.Schema
  import Ecto.Changeset

  alias CartographBackend.Ids

  # Slug part of the public job id: lowercase alphanumerics and single hyphens.
  @identifier_format ~r/^[a-z0-9]+(-[a-z0-9]+)*$/

  schema "task_definition" do
    field :name, :string
    field :description, :string
    field :identifier, :string
    field :code, :string
    field :dsl, :string
    field :cron, :string
    # Cumulative token cap (input + output) across all agent steps of one
    # execution; nil falls back to the server default (200k). Applies to the
    # root job of the execution, including agent steps inlined via `use`.
    field :agent_token_budget, :integer
    field :project_id, :integer
    field :release_at, :utc_datetime_usec
    field :archive_at, :utc_datetime_usec
    field :created_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  def changeset(task_def, attrs) do
    task_def
    |> cast(attrs, [
      :name,
      :description,
      :identifier,
      :dsl,
      :cron,
      :agent_token_budget,
      :project_id,
      :release_at,
      :archive_at
    ])
    |> validate_required([:name, :identifier, :dsl])
    |> validate_length(:name, min: 1)
    |> validate_format(:identifier, @identifier_format,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> validate_release_before_archive()
    |> put_new_code()
    |> unique_constraint(:code)
    |> put_new_created_at()
    |> put_change(:updated_at, DateTime.utc_now())
  end

  # `identifier` is immutable: it is not cast here, so the public job id is
  # stable for the life of the job.
  def update_changeset(task_def, attrs) do
    task_def
    |> cast(attrs, [
      :name,
      :description,
      :dsl,
      :cron,
      :agent_token_budget,
      :project_id,
      :release_at,
      :archive_at
    ])
    |> validate_length(:name, min: 1)
    |> validate_release_before_archive()
    |> put_change(:updated_at, DateTime.utc_now())
  end

  # Derive `code` (`"<identifier>-<suffix>"`) only on insert of a valid changeset;
  # never overwrite on update.
  defp put_new_code(%{valid?: true, data: %{id: nil, code: nil}} = cs),
    do: put_change(cs, :code, Ids.generate_job_code(__MODULE__, get_field(cs, :identifier)))

  defp put_new_code(cs), do: cs

  # Archive date, when both are set, must be after the release date.
  defp validate_release_before_archive(changeset) do
    release = get_field(changeset, :release_at)
    archive = get_field(changeset, :archive_at)

    if release && archive && DateTime.compare(archive, release) != :gt do
      add_error(changeset, :archive_at, "must be after the release date")
    else
      changeset
    end
  end

  defp put_new_created_at(%{data: %{id: nil}} = cs),
    do: put_change(cs, :created_at, DateTime.utc_now())

  defp put_new_created_at(cs), do: cs
end
