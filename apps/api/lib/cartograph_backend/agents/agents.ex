defmodule CartographBackend.Agents do
  @moduledoc """
  Anthropic API credentials registered per project. Managing them requires the
  `:manage_secrets` level (Navigator+) on the project; the `agent` step
  resolves them by public `code` at runtime, scoped to the executing project.
  """

  import Ecto.Query
  alias CartographBackend.Repo
  alias CartographBackend.Agents.AnthropicCredential

  def list_for_project(project_id) do
    Repo.all(from c in AnthropicCredential, where: c.project_id == ^project_id, order_by: c.name)
  end

  def get(id) do
    case Repo.get(AnthropicCredential, id) do
      nil -> {:error, :not_found}
      c -> {:ok, c}
    end
  end

  def get_credential_by_code(code) do
    case Repo.get_by(AnthropicCredential, code: code) do
      nil -> {:error, :not_found}
      c -> {:ok, c}
    end
  end

  def create(attrs) do
    %AnthropicCredential{} |> AnthropicCredential.changeset(attrs) |> Repo.insert()
  end

  def update(%AnthropicCredential{} = credential, attrs) do
    credential |> AnthropicCredential.changeset(attrs) |> Repo.update()
  end

  def delete(%AnthropicCredential{} = credential), do: Repo.delete(credential)
end
