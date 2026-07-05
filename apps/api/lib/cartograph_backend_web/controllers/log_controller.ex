defmodule CartographBackendWeb.LogController do
  use CartographBackendWeb, :controller

  alias CartographBackend.{Executions, Authorization, Repo}
  alias CartographBackend.Executions.{TaskExecution, Status}
  alias CartographBackendWeb.{Serializers, Params}

  def history(conn, %{"id" => id}) do
    with {:ok, eid} <- Params.int(id),
         %TaskExecution{} = execution <- Repo.get(TaskExecution, eid),
         :ok <- Authorization.authorize_execution(conn.assigns.current_user, :view, execution) do
      logs = Executions.list_logs(execution.id)
      json(conn, Enum.map(logs, &Serializers.execution_log/1))
    else
      {:error, :bad_request} -> conn |> put_status(400) |> json(%{error: "Bad request"})
      {:error, :forbidden} -> conn |> put_status(403) |> json(%{error: "Forbidden"})
      nil -> send_resp(conn, 404, "")
    end
  end

  def stream(conn, %{"id" => id}) do
    with {:ok, execution_id} <- Params.int(id),
         %TaskExecution{} = execution <- Repo.get(TaskExecution, execution_id),
         :ok <- Authorization.authorize_execution(conn.assigns.current_user, :view, execution) do
      conn =
        conn
        |> put_resp_content_type("text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("x-accel-buffering", "no")
        |> send_chunked(200)

      # Subscribe before checking status to avoid missing events
      Phoenix.PubSub.subscribe(CartographBackend.PubSub, "execution:#{execution_id}")

      if Status.terminal?(execution.status) do
        conn
      else
        stream_loop(conn)
      end
    else
      {:error, :bad_request} -> conn |> put_status(400) |> json(%{error: "Bad request"})
      {:error, :forbidden} -> conn |> put_status(403) |> json(%{error: "Forbidden"})
      nil -> send_resp(conn, 404, "")
    end
  end

  defp stream_loop(conn) do
    receive do
      {:log, log} ->
        data = Jason.encode!(Serializers.execution_log(log))

        case chunk(conn, "data: #{data}\n\n") do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end

      :execution_complete ->
        conn

    after
      30_000 ->
        case chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end
    end
  end
end
