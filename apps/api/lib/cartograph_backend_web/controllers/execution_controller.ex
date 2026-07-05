defmodule CartographBackendWeb.ExecutionController do
  use CartographBackendWeb, :controller

  alias CartographBackend.{Executions, Authorization}
  alias CartographBackendWeb.{Serializers, Params}

  def index(conn, params) do
    user = conn.assigns.current_user
    visible = Authorization.scope(user).tasks

    with {:ok, opts} <- index_opts(params) do
      executions =
        Executions.list_executions(opts)
        |> Enum.filter(&Map.has_key?(visible, &1.task_definition_id))

      json(conn, Enum.map(executions, &Serializers.task_execution/1))
    else
      {:error, :bad_request} -> bad_request(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, eid} <- Params.int(id),
         {:ok, %{execution: execution, steps: steps}} <- Executions.get_execution(eid),
         :ok <- Authorization.authorize_execution(conn.assigns.current_user, :view, execution) do
      json(conn, %{
        execution: Serializers.task_execution(execution),
        steps: Enum.map(steps, &Serializers.step_execution/1)
      })
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  def stop(conn, %{"id" => id}) do
    with {:ok, eid} <- Params.int(id),
         {:ok, %{execution: execution}} <- Executions.get_execution(eid),
         :ok <- Authorization.authorize_execution(conn.assigns.current_user, :run, execution),
         {:ok, _} <- Executions.stop(execution.id) do
      send_resp(conn, 200, "")
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
      {:error, :not_running} -> conn |> put_status(422) |> json(%{error: "Execution is not running"})
    end
  end

  defp index_opts(%{"taskId" => task_id}) do
    with {:ok, tid} <- Params.int(task_id), do: {:ok, [task_id: tid]}
  end

  defp index_opts(_params), do: {:ok, []}
end
