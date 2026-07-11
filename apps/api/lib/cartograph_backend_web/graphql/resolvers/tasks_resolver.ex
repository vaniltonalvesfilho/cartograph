defmodule CartographBackendWeb.Graphql.Resolvers.Tasks do
  alias CartographBackend.{Tasks, Accounts}
  alias CartographBackendWeb.Graphql.Authz

  def list(_parent, args, res) do
    levels = Authz.scope(res).tasks
    opts = if pid = Authz.to_id(args[:project_id]), do: [project_id: pid], else: []

    tasks =
      Tasks.list_tasks(opts)
      |> Enum.filter(&Map.has_key?(levels, &1.id))

    {:ok, tasks}
  end

  def get(_parent, %{id: id}, res) do
    with {:ok, task} <- Tasks.get_task(Authz.to_id(id)),
         :ok <- Authz.authorize(res, :view, task) do
      {:ok, task}
    end
  end

  def create(_parent, args, res) do
    user = Authz.current_user(res)
    project_id = Authz.to_id(args[:project_id])

    with :ok <- Authz.authorize_create_task(res, project_id),
         {:ok, task} <-
           Tasks.create_task(
             %{
               "name" => args.name,
               "identifier" => args.identifier,
               "dsl" => args.dsl,
               "cron" => args[:cron],
               "agent_token_budget" => args[:agent_token_budget],
               "project_id" => project_id,
               "release_at" => args[:release_at],
               "archive_at" => args[:archive_at]
             },
             user
           ) do
      Accounts.grant_owner(user, "task", task.id)
      {:ok, task}
    end
  end

  def update(_parent, %{id: id} = args, res) do
    user = Authz.current_user(res)
    attrs = args |> Map.drop([:id, :project_id]) |> atom_to_string_keys()
    attrs = maybe_put_project(attrs, args)

    with {:ok, task} <- Tasks.get_task(Authz.to_id(id)),
         :ok <- Authz.authorize(res, :edit, task),
         :ok <- Authz.authorize_move_task(res, Map.get(attrs, "project_id", :unchanged)),
         {:ok, task} <- Tasks.update_task(task.id, attrs, user) do
      {:ok, task}
    end
  end

  def delete(_parent, %{id: id}, res) do
    with {:ok, task} <- Tasks.get_task(Authz.to_id(id)),
         :ok <- Authz.authorize(res, :delete, task),
         {:ok, _} <- Tasks.delete_task(task.id) do
      {:ok, true}
    end
  end

  def run(_parent, %{id: id}, res) do
    with {:ok, task} <- Tasks.get_task(Authz.to_id(id)),
         :ok <- Authz.authorize(res, :run, task),
         {:ok, result} <- Tasks.run(task.id) do
      {:ok, result}
    else
      {:error, :not_found} = err -> err
      {:error, "forbidden"} = err -> err
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp maybe_put_project(attrs, args) do
    if Map.has_key?(args, :project_id),
      do: Map.put(attrs, "project_id", Authz.to_id(args[:project_id])),
      else: attrs
  end

  defp atom_to_string_keys(map) do
    Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)
  end
end
