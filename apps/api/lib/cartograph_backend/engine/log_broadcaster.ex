defmodule CartographBackend.Engine.LogBroadcaster do
  @moduledoc """
  Persists a log line to the database AND broadcasts it via Phoenix.PubSub
  so every node that has an SSE client subscribed to "execution:{id}" receives it.

  This replaces the in-memory BroadcastProcessor from the Java implementation,
  enabling distributed log streaming without any external message broker.
  """

  alias CartographBackend.Repo
  alias CartographBackend.Executions.ExecutionLog

  @doc "Persists and broadcasts a log line."
  def log(execution_id, step_execution_id, level, message) do
    attrs = %{
      execution_id: execution_id,
      step_execution_id: step_execution_id,
      level: level,
      message: message,
      timestamp: DateTime.utc_now()
    }

    case Repo.insert(struct(ExecutionLog, attrs)) do
      {:ok, saved} ->
        Phoenix.PubSub.broadcast(
          CartographBackend.PubSub,
          "execution:#{execution_id}",
          {:log, saved}
        )

        Absinthe.Subscription.publish(
          CartographBackendWeb.Endpoint,
          saved,
          execution_log: "execution:#{execution_id}"
        )

        :ok

      {:error, changeset} ->
        require Logger
        Logger.error("Failed to persist log: #{inspect(changeset.errors)}")
        :ok
    end
  end

  @doc "Signals SSE clients that the execution stream is finished."
  def complete(execution_id) do
    Phoenix.PubSub.broadcast(
      CartographBackend.PubSub,
      "execution:#{execution_id}",
      :execution_complete
    )
  end
end
