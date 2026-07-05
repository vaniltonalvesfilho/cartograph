defmodule CartographBackend.DataSources do
  import Ecto.Query
  alias CartographBackend.Repo
  alias CartographBackend.DataSources.{DataSource, DataSourceProject}
  alias CartographBackend.Vault

  def list_all do
    Repo.all(from ds in DataSource, preload: [:projects])
  end

  def list_for_project(project_id) do
    Repo.all(
      from ds in DataSource,
        join: dsp in DataSourceProject, on: dsp.data_source_id == ds.id,
        where: dsp.project_id == ^project_id,
        preload: [:projects]
    )
  end

  def get(id) do
    case Repo.get(DataSource, id) do
      nil -> {:error, :not_found}
      ds  -> {:ok, Repo.preload(ds, :projects)}
    end
  end

  def get_by_slug(slug) do
    case Repo.get_by(DataSource, slug: slug) do
      nil -> {:error, :not_found}
      ds  -> {:ok, ds}
    end
  end

  def create(attrs) do
    case %DataSource{} |> DataSource.changeset(attrs) |> Repo.insert() do
      {:ok, ds}    -> {:ok, Repo.preload(ds, :projects)}
      {:error, cs} -> {:error, cs}
    end
  end

  def update(id, attrs) do
    with {:ok, ds} <- get(id) do
      case ds |> DataSource.changeset(attrs) |> Repo.update() do
        {:ok, updated} -> {:ok, Repo.preload(updated, :projects)}
        {:error, cs}   -> {:error, cs}
      end
    end
  end

  def delete(id) do
    with {:ok, ds} <- get(id), do: Repo.delete(ds)
  end

  def assign_to_project(data_source_id, project_id) do
    case %DataSourceProject{}
         |> DataSourceProject.changeset(%{data_source_id: data_source_id, project_id: project_id})
         |> Repo.insert(on_conflict: :nothing) do
      {:ok, _}     -> :ok
      {:error, cs} -> {:error, cs}
    end
  end

  def remove_from_project(data_source_id, project_id) do
    Repo.delete_all(
      from dsp in DataSourceProject,
        where: dsp.data_source_id == ^data_source_id and dsp.project_id == ^project_id
    )
    :ok
  end

  def project_has_access?(project_id, data_source_id) do
    Repo.exists?(
      from dsp in DataSourceProject,
        where: dsp.data_source_id == ^data_source_id and dsp.project_id == ^project_id
    )
  end

  def health_check(%DataSource{} = ds) do
    password = Vault.decrypt(ds.password_encrypted)
    t0 = System.monotonic_time(:millisecond)

    result =
      case ds.adapter do
        "postgres" -> ping_postgres(ds, password)
        "mysql"    -> ping_mysql(ds, password)
        other      -> {:error, "unsupported adapter: #{other}"}
      end

    latency = System.monotonic_time(:millisecond) - t0

    case result do
      :ok              -> {:ok, latency}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ping_postgres(ds, password) do
    opts = conn_opts(ds, password)
    with {:ok, pid} <- Postgrex.start_link(opts),
         {:ok, _}   <- Postgrex.query(pid, "SELECT 1", []) do
      GenServer.stop(pid, :normal)
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp ping_mysql(ds, password) do
    opts = conn_opts(ds, password)
    with {:ok, pid} <- MyXQL.start_link(opts),
         {:ok, _}   <- MyXQL.query(pid, "SELECT 1") do
      GenServer.stop(pid, :normal)
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp conn_opts(ds, password) do
    [
      hostname:        ds.host,
      port:            ds.port,
      database:        ds.database_name,
      username:        ds.username,
      password:        password || "",
      ssl:             ds.ssl,
      connect_timeout: 5_000,
      timeout:         5_000
    ]
  end
end
