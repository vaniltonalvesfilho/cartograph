defmodule CartographBackendWeb.TaskController do
  use CartographBackendWeb, :controller

  alias CartographBackend.{Tasks, Accounts, Authorization}
  alias CartographBackendWeb.{Serializers, Params}

  def index(conn, params) do
    user = conn.assigns.current_user
    levels = Authorization.scope(user).tasks

    with {:ok, opts} <- index_opts(params) do
      tasks =
        Tasks.list_tasks(opts)
        |> Enum.filter(&Map.has_key?(levels, &1.id))
        |> Enum.map(&Serializers.task_definition(&1, Map.fetch!(levels, &1.id)))

      json(conn, tasks)
    else
      {:error, :bad_request} -> bad_request(conn)
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    attrs =
      params
      |> Map.take([
        "name",
        "description",
        "identifier",
        "dsl",
        "cron",
        "agentTokenBudget",
        "projectId",
        "releaseAt",
        "archiveAt"
      ])
      |> rename_key("projectId", "project_id")
      |> rename_key("releaseAt", "release_at")
      |> rename_key("archiveAt", "archive_at")
      |> rename_key("agentTokenBudget", "agent_token_budget")

    with :ok <- Authorization.authorize_create_task(user, attrs["project_id"]),
         {:ok, task} <- Tasks.create_task(attrs, user) do
      Accounts.grant_owner(user, "task", task.id)
      level = Authorization.effective_level(user, task)
      conn |> put_status(201) |> json(Serializers.task_definition(task, level))
    else
      {:error, :forbidden} -> forbidden(conn)
      {:error, %Ecto.Changeset{} = cs} -> unprocessable(conn, cs)
      {:error, reason} when is_binary(reason) -> conn |> put_status(400) |> json(%{error: reason})
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    attrs =
      params
      |> Map.take([
        "name",
        "description",
        "dsl",
        "cron",
        "agentTokenBudget",
        "projectId",
        "releaseAt",
        "archiveAt"
      ])
      |> rename_key("projectId", "project_id")
      |> rename_key("releaseAt", "release_at")
      |> rename_key("archiveAt", "archive_at")
      |> rename_key("agentTokenBudget", "agent_token_budget")

    with {:ok, tid} <- Params.int(id),
         {:ok, task} <- Tasks.get_task(tid),
         :ok <- Authorization.authorize(user, :edit, task),
         :ok <- Authorization.authorize_move_task(user, Map.get(attrs, "project_id", :unchanged)),
         {:ok, task} <- Tasks.update_task(task.id, attrs, user) do
      json(conn, Serializers.task_definition(task, Authorization.effective_level(user, task)))
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
      {:error, %Ecto.Changeset{} = cs} -> unprocessable(conn, cs)
      {:error, reason} when is_binary(reason) -> conn |> put_status(400) |> json(%{error: reason})
    end
  end

  # Must be declared before delete/run that use :id
  def available_steps(conn, _params) do
    json(conn, Tasks.available_steps())
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, tid} <- Params.int(id),
         {:ok, task} <- Tasks.get_task(tid),
         :ok <- Authorization.authorize(user, :delete, task),
         {:ok, _} <- Tasks.delete_task(task.id) do
      send_resp(conn, 204, "")
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  def run(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, tid} <- Params.int(id),
         {:ok, task} <- Tasks.get_task(tid),
         :ok <- Authorization.authorize(user, :run, task),
         {:ok, %{execution_id: eid}} <- Tasks.run(task.id) do
      json(conn, %{executionId: eid})
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
      {:error, reason} when is_binary(reason) -> conn |> put_status(400) |> json(%{error: reason})
      {:error, _} -> conn |> put_status(500) |> json(%{error: "Internal error"})
    end
  end

  # Cross-job reference graph over the tasks the viewer can see. Refs to jobs
  # outside that set yield no edge (no enumeration oracle).
  def graph(conn, _params) do
    user = conn.assigns.current_user
    levels = Authorization.scope(user).tasks

    tasks =
      Tasks.list_tasks()
      |> Enum.filter(&Map.has_key?(levels, &1.id))

    json(conn, CartographBackend.Tasks.Graph.build(tasks))
  end

  # Visualizable execution flow (steps + branches + inlined sub-jobs). Sub-jobs
  # the viewer can't see collapse to a generic node inside Flow.build.
  def flow(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, tid} <- Params.int(id),
         {:ok, task} <- Tasks.get_task(tid),
         :ok <- Authorization.authorize(user, :view, task),
         {:ok, nodes} <- CartographBackend.Dsl.Flow.build(task.dsl, %{user: user}, task.code) do
      json(conn, %{flow: nodes})
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
      {:error, reason} when is_binary(reason) -> conn |> put_status(400) |> json(%{error: reason})
    end
  end

  defp index_opts(%{"projectId" => pid}) do
    with {:ok, project_id} <- Params.int(pid), do: {:ok, [project_id: project_id]}
  end

  defp index_opts(_params), do: {:ok, []}

  defp rename_key(map, from, to) do
    case Map.pop(map, from) do
      {nil, map} -> map
      {val, map} -> Map.put(map, to, val)
    end
  end
end
