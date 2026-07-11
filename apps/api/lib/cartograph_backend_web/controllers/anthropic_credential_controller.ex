defmodule CartographBackendWeb.AnthropicCredentialController do
  use CartographBackendWeb, :controller

  alias CartographBackend.{Agents, Authorization, Groups}
  alias CartographBackendWeb.Serializers

  # Listing needs only :view — Explorers writing DSL need the codes; the API
  # key itself is never serialized. Create/update/delete require
  # :manage_secrets (Navigator+ on the project).

  def index(conn, %{"project_id" => project_id}) do
    with_project(conn, project_id, :view, fn project ->
      credentials = Agents.list_for_project(project.id)
      json(conn, Enum.map(credentials, &Serializers.anthropic_credential/1))
    end)
  end

  def create(conn, %{"project_id" => project_id} = params) do
    with_project(conn, project_id, :manage_secrets, fn project ->
      attrs = credential_attrs(params) |> Map.put("project_id", project.id)

      case Agents.create(attrs) do
        {:ok, credential} ->
          conn |> put_status(201) |> json(Serializers.anthropic_credential(credential))

        {:error, cs} ->
          unprocessable(conn, cs)
      end
    end)
  end

  def update(conn, %{"project_id" => project_id, "id" => id} = params) do
    with_project(conn, project_id, :manage_secrets, fn project ->
      with_credential(conn, project, id, fn credential ->
        # project_id is not taken from the payload: a credential never moves.
        attrs = params |> credential_attrs() |> Map.delete("project_id")

        case Agents.update(credential, attrs) do
          {:ok, updated} -> json(conn, Serializers.anthropic_credential(updated))
          {:error, cs} -> unprocessable(conn, cs)
        end
      end)
    end)
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    with_project(conn, project_id, :manage_secrets, fn project ->
      with_credential(conn, project, id, fn credential ->
        {:ok, _} = Agents.delete(credential)
        send_resp(conn, 204, "")
      end)
    end)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  # Payload is camelCase in (`{"credential": {"name": …, "apiKey": …}}`); the
  # changeset expects `api_key`. A blank key on update means "keep the stored
  # one", so it is dropped rather than passed through as "".
  defp credential_attrs(params) do
    attrs = params["credential"] || %{}

    case Map.pop(attrs, "apiKey") do
      {nil, rest} -> rest
      {"", rest} -> rest
      {api_key, rest} -> Map.put(rest, "api_key", api_key)
    end
  end

  defp with_project(conn, id, action, fun) do
    with int_id when is_integer(int_id) <- to_int(id),
         {:ok, project} <- Groups.get_project(int_id),
         true <- Authorization.can?(conn.assigns.current_user, action, project) do
      fun.(project)
    else
      nil -> conn |> put_status(400) |> json(%{error: "Bad request"})
      false -> conn |> put_status(403) |> json(%{error: "Forbidden"})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "Not found"})
    end
  end

  defp with_credential(conn, project, id, fun) do
    with int_id when is_integer(int_id) <- to_int(id),
         {:ok, credential} <- Agents.get(int_id),
         true <- credential.project_id == project.id do
      fun.(credential)
    else
      nil -> conn |> put_status(400) |> json(%{error: "Bad request"})
      # A credential of another project is reported as absent, not forbidden.
      _ -> conn |> put_status(404) |> json(%{error: "Not found"})
    end
  end

  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp to_int(_), do: nil
end
