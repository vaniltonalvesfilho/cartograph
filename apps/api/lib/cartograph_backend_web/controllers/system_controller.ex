defmodule CartographBackendWeb.SystemController do
  use CartographBackendWeb, :controller

  alias CartographBackend.SystemMetrics

  def metrics(conn, _params) do
    json(conn, SystemMetrics.collect())
  end

  def health(conn, _params) do
    json(conn, %{status: "ok", node: node(), timestamp: DateTime.utc_now()})
  end
end
