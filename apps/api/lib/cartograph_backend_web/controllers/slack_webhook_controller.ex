defmodule CartographBackendWeb.SlackWebhookController do
  use CartographBackendWeb, :controller

  alias CartographBackend.{Authorization, Groups, Webhooks}
  alias CartographBackendWeb.Serializers

  # Listing needs only :view — Explorers writing DSL need the codes; the URL
  # itself is never serialized. Create/update/delete require :manage_secrets
  # (Navigator+ on the project).

  def index(conn, %{"project_id" => project_id}) do
    with_project(conn, project_id, :view, fn project ->
      webhooks = Webhooks.list_for_project(project.id)
      json(conn, Enum.map(webhooks, &Serializers.slack_webhook/1))
    end)
  end

  def create(conn, %{"project_id" => project_id} = params) do
    with_project(conn, project_id, :manage_secrets, fn project ->
      attrs = Map.put(params["webhook"] || %{}, "project_id", project.id)

      case Webhooks.create(attrs) do
        {:ok, webhook} -> conn |> put_status(201) |> json(Serializers.slack_webhook(webhook))
        {:error, cs} -> unprocessable(conn, cs)
      end
    end)
  end

  def update(conn, %{"project_id" => project_id, "id" => id} = params) do
    with_project(conn, project_id, :manage_secrets, fn project ->
      with_webhook(conn, project, id, fn webhook ->
        # project_id is not taken from the payload: a webhook never moves.
        attrs = Map.delete(params["webhook"] || %{}, "project_id")

        case Webhooks.update(webhook, attrs) do
          {:ok, updated} -> json(conn, Serializers.slack_webhook(updated))
          {:error, cs} -> unprocessable(conn, cs)
        end
      end)
    end)
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    with_project(conn, project_id, :manage_secrets, fn project ->
      with_webhook(conn, project, id, fn webhook ->
        {:ok, _} = Webhooks.delete(webhook)
        send_resp(conn, 204, "")
      end)
    end)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

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

  defp with_webhook(conn, project, id, fun) do
    with int_id when is_integer(int_id) <- to_int(id),
         {:ok, webhook} <- Webhooks.get(int_id),
         true <- webhook.project_id == project.id do
      fun.(webhook)
    else
      nil -> conn |> put_status(400) |> json(%{error: "Bad request"})
      # A webhook of another project is reported as absent, not forbidden.
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
