defmodule CartographBackend.Groups.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias CartographBackend.Ids

  schema "projects" do
    field :name, :string
    field :description, :string
    field :code, :string
    field :group_id, :integer
    field :position, :integer, default: 0
    field :created_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :group_id, :position])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> put_new_code()
    |> unique_constraint(:code)
    |> put_new_created_at()
    |> put_change(:updated_at, DateTime.utc_now())
  end

  # Set `code` only on insert (new row, no code yet); never overwrite on update.
  defp put_new_code(%{data: %{id: nil, code: nil}} = cs),
    do: put_change(cs, :code, Ids.generate_code(__MODULE__))

  defp put_new_code(cs), do: cs

  defp put_new_created_at(%{data: %{id: nil}} = cs),
    do: put_change(cs, :created_at, DateTime.utc_now())

  defp put_new_created_at(cs), do: cs
end
