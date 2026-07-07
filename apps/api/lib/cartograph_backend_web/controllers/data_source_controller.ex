defmodule CartographBackendWeb.DataSourceController do
  use CartographBackendWeb, :controller

  alias CartographBackend.DataSources
  alias CartographBackendWeb.Serializers

  # ── Admin: CRUD ──────────────────────────────────────────────────────────────

  def index(conn, _params) do
    with :ok <- require_admin(conn) do
      sources = DataSources.list_all()
      json(conn, Enum.map(sources, &Serializers.data_source(&1, :admin)))
    else
      {:error, conn} -> conn
    end
  end

  def create(conn, %{"data_source" => attrs}) do
    with :ok <- require_admin(conn) do
      case DataSources.create(attrs) do
        {:ok, ds} -> conn |> put_status(201) |> json(Serializers.data_source(ds, :admin))
        {:error, cs} -> unprocessable(conn, cs)
      end
    else
      {:error, conn} -> conn
    end
  end

  def update(conn, %{"id" => id, "data_source" => attrs}) do
    with :ok <- require_admin(conn),
         {:ok, int_id} <- parse_int(conn, id) do
      case DataSources.update(int_id, attrs) do
        {:ok, ds} -> json(conn, Serializers.data_source(ds, :admin))
        {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "Not found"})
        {:error, cs} -> unprocessable(conn, cs)
      end
    else
      {:error, conn} -> conn
    end
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- require_admin(conn),
         {:ok, int_id} <- parse_int(conn, id) do
      case DataSources.delete(int_id) do
        {:ok, _} -> send_resp(conn, 204, "")
        {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "Not found"})
      end
    else
      {:error, conn} -> conn
    end
  end

  def health(conn, %{"id" => id}) do
    with :ok <- require_admin(conn),
         {:ok, int_id} <- parse_int(conn, id),
         {:ok, ds} <- DataSources.get(int_id) do
      case DataSources.health_check(ds) do
        {:ok, latency} -> json(conn, %{status: "ok", latencyMs: latency})
        {:error, reason} -> json(conn, %{status: "error", error: reason})
      end
    else
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "Not found"})
      {:error, halted_conn} -> halted_conn
    end
  end

  # ── Project-scoped data sources ───────────────────────────────────────────────

  def index_for_project(conn, %{"project_id" => project_id}) do
    with {:ok, int_id} <- parse_int(conn, project_id) do
      sources = DataSources.list_for_project(int_id)
      user = conn.assigns.current_user

      serialized =
        Enum.map(sources, fn ds ->
          if user.is_admin,
            do: Serializers.data_source(ds, :admin),
            else: Serializers.data_source(ds)
        end)

      json(conn, serialized)
    else
      {:error, conn} -> conn
    end
  end

  def assign(conn, %{"project_id" => project_id, "data_source_id" => ds_id}) do
    with :ok <- require_admin(conn),
         {:ok, int_project_id} <- parse_int(conn, project_id),
         {:ok, int_ds_id} <- parse_int(conn, ds_id) do
      case DataSources.assign_to_project(int_ds_id, int_project_id) do
        :ok -> send_resp(conn, 204, "")
        {:error, cs} -> unprocessable(conn, cs)
      end
    else
      {:error, conn} -> conn
    end
  end

  def unassign(conn, %{"project_id" => project_id, "data_source_id" => ds_id}) do
    with :ok <- require_admin(conn),
         {:ok, int_project_id} <- parse_int(conn, project_id),
         {:ok, int_ds_id} <- parse_int(conn, ds_id) do
      DataSources.remove_from_project(int_ds_id, int_project_id)
      send_resp(conn, 204, "")
    else
      {:error, conn} -> conn
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp parse_int(_conn, value) when is_integer(value), do: {:ok, value}

  defp parse_int(conn, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, conn |> put_status(400) |> json(%{error: "Bad request"}) |> halt()}
    end
  end
end
