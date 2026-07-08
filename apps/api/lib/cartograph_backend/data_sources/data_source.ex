defmodule CartographBackend.DataSources.DataSource do
  use Ecto.Schema
  import Ecto.Changeset
  alias CartographBackend.Vault

  schema "data_sources" do
    field :name, :string
    field :slug, :string
    field :adapter, :string
    field :host, :string
    field :port, :integer
    field :database_name, :string
    field :username, :string
    field :password_encrypted, :binary
    field :password, :string, virtual: true
    field :ssl, :boolean, default: false
    field :notes, :string

    many_to_many :projects, CartographBackend.Groups.Project,
      join_through: "data_source_projects",
      join_keys: [data_source_id: :id, project_id: :id]

    timestamps()
  end

  @adapters ~w(postgres mysql)

  def changeset(ds, attrs) do
    ds
    |> cast(attrs, [
      :name,
      :slug,
      :adapter,
      :host,
      :port,
      :database_name,
      :username,
      :password,
      :ssl,
      :notes
    ])
    |> validate_required([:name, :slug, :adapter, :host, :port, :database_name, :username])
    |> validate_inclusion(:adapter, @adapters, message: "must be 'postgres' or 'mysql'")
    |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
      message: "must be lowercase slug (e.g. mysql-local)"
    )
    |> unique_constraint(:slug)
    |> validate_number(:port, greater_than: 0, less_than_or_equal_to: 65_535)
    |> encrypt_password()
  end

  defp encrypt_password(cs) do
    case get_change(cs, :password) do
      nil -> cs
      pw -> put_change(cs, :password_encrypted, Vault.encrypt(pw))
    end
  end
end
