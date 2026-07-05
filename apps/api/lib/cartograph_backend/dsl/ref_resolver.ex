defmodule CartographBackend.Dsl.RefResolver do
  @moduledoc """
  Resolves a job reference (`use`/`job` → the job's public `code`) to the
  referenced `TaskDefinition`, enforcing `:view` authorization.

  Shared by `Expander` (flattens refs for execution) and `Flow` (keeps them
  structured for visualization) so the resolution + auth rule lives in one place.

  A `:system` context (cron/server runs) bypasses the check — refs were vetted at
  author time. A nonexistent job and a forbidden job are indistinguishable (both
  `:error`) so there is no enumeration oracle.
  """

  import Ecto.Query

  alias CartographBackend.Repo
  alias CartographBackend.Authorization
  alias CartographBackend.Tasks.TaskDefinition

  @type ctx :: %{optional(:user) => any()} | :system

  @doc """
  Returns `{:ok, task}` when the job `code` exists and the context's user may
  `:view` it, otherwise `:error` (same outcome for not-found and forbidden).
  """
  @spec resolve(String.t(), ctx) :: {:ok, struct()} | :error
  def resolve(code, ctx) when is_binary(code) do
    with %TaskDefinition{} = task <-
           Repo.one(from t in TaskDefinition, where: t.code == ^code, limit: 1),
         true <- authorized?(user(ctx), task) do
      {:ok, task}
    else
      _ -> :error
    end
  end

  def resolve(_code, _ctx), do: :error

  defp user(:system), do: :system
  defp user(%{user: u}), do: u
  defp user(_), do: nil

  defp authorized?(:system, _task), do: true
  defp authorized?(user, task), do: Authorization.authorize(user, :view, task) == :ok
end
