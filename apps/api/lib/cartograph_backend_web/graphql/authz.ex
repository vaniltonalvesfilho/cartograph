defmodule CartographBackendWeb.Graphql.Authz do
  @moduledoc """
  Authorization helpers shared by GraphQL resolvers.

  Mirrors the checks the REST controllers perform: the resolution context
  carries the authenticated user (populated by `AbsintheContext`), and every
  resolver must authorize the action against the target resource before acting.
  """

  alias CartographBackend.{Authorization, Executions}

  @doc "The authenticated user from the Absinthe resolution, or nil."
  def current_user(%{context: %{current_user: user}}), do: user
  def current_user(_), do: nil

  @doc """
  Authorizes `action` on `resource` for the resolution's user.
  Returns `:ok` or `{:error, "forbidden"}`. A nil resource only passes for
  global admins (used for orphaned executions whose task was deleted).
  """
  def authorize(resolution, action, resource) do
    if Authorization.can?(current_user(resolution), action, resource),
      do: :ok,
      else: {:error, "forbidden"}
  end

  @doc "Effective level of the resolution's user on a resource."
  def effective_level(resolution, resource),
    do: Authorization.effective_level(current_user(resolution), resource)

  @doc "Visibility scope (groups/projects/tasks → level) for the resolution's user."
  def scope(resolution), do: Authorization.scope(current_user(resolution))

  # ── Action policies (delegate to the Authorization context, string errors) ────

  def authorize_create_group(res, parent_id), do: gql(Authorization.authorize_create_group(current_user(res), parent_id))
  def authorize_create_project(res, group_id), do: gql(Authorization.authorize_create_project(current_user(res), group_id))
  def authorize_create_task(res, project_id), do: gql(Authorization.authorize_create_task(current_user(res), project_id))
  def authorize_move_project(res, group_id), do: gql(Authorization.authorize_move_project(current_user(res), group_id))
  def authorize_move_task(res, project_id), do: gql(Authorization.authorize_move_task(current_user(res), project_id))

  @doc "Authorizes `action` on an execution struct for the resolution's user."
  def authorize_execution(res, action, execution),
    do: gql(Authorization.authorize_execution(current_user(res), action, execution))

  @doc """
  Authorizes `action` on the execution identified by `execution_id`, for a raw
  user (used by subscriptions, which carry the user in the socket context).
  """
  def authorize_execution_id(user, action, execution_id) do
    case Executions.get_execution(to_id(execution_id)) do
      {:ok, %{execution: execution}} -> gql(Authorization.authorize_execution(user, action, execution))
      {:error, :not_found} -> {:error, "forbidden"}
    end
  end

  @doc """
  Authorizes `action` on the task identified by `task_id`, for a raw user
  (used by subscriptions, which carry the user in the socket context).
  """
  def authorize_task_id(user, action, task_id) do
    case CartographBackend.Tasks.get_task(to_id(task_id)) do
      {:ok, task} ->
        if Authorization.can?(user, action, task), do: :ok, else: {:error, "forbidden"}

      {:error, :not_found} ->
        {:error, "forbidden"}
    end
  end

  defp gql(:ok), do: :ok
  defp gql({:error, :forbidden}), do: {:error, "forbidden"}

  @doc "Parses a GraphQL `:id` argument to an integer, or nil when malformed/absent."
  def to_id(nil), do: nil
  def to_id(id) when is_integer(id), do: id
  def to_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
