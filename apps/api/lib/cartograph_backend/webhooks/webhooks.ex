defmodule CartographBackend.Webhooks do
  @moduledoc """
  Slack incoming webhooks registered per project. Managing them requires the
  `:manage_secrets` level (Navigator+) on the project; the `notify` step
  resolves them by public `code` at runtime, scoped to the executing project.
  """

  import Ecto.Query
  alias CartographBackend.Repo
  alias CartographBackend.Webhooks.SlackWebhook

  def list_for_project(project_id) do
    Repo.all(from w in SlackWebhook, where: w.project_id == ^project_id, order_by: w.name)
  end

  def get(id) do
    case Repo.get(SlackWebhook, id) do
      nil -> {:error, :not_found}
      w -> {:ok, w}
    end
  end

  def get_by_code(code) do
    case Repo.get_by(SlackWebhook, code: code) do
      nil -> {:error, :not_found}
      w -> {:ok, w}
    end
  end

  def create(attrs) do
    %SlackWebhook{} |> SlackWebhook.changeset(attrs) |> Repo.insert()
  end

  def update(%SlackWebhook{} = webhook, attrs) do
    webhook |> SlackWebhook.changeset(attrs) |> Repo.update()
  end

  def delete(%SlackWebhook{} = webhook), do: Repo.delete(webhook)
end
