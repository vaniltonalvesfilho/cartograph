defmodule CartographBackendWeb.Graphql.Resolvers.Executions do
  alias CartographBackend.Executions
  alias CartographBackendWeb.Graphql.Authz

  def list(_parent, args, res) do
    visible = Authz.scope(res).tasks
    opts = if tid = Authz.to_id(args[:task_id]), do: [task_id: tid], else: []

    executions =
      Executions.list_executions(opts)
      |> Enum.filter(&Map.has_key?(visible, &1.task_definition_id))

    executions = if limit = args[:limit], do: Enum.take(executions, limit), else: executions
    {:ok, executions}
  end

  def get(_parent, %{id: id}, res) do
    with {:ok, %{execution: execution}} <- Executions.get_execution(Authz.to_id(id)),
         :ok <- Authz.authorize_execution(res, :view, execution) do
      {:ok, execution}
    end
  end

  def list_steps(_parent, %{execution_id: id}, res) do
    with {:ok, %{execution: execution, steps: steps}} <-
           Executions.get_execution(Authz.to_id(id)),
         :ok <- Authz.authorize_execution(res, :view, execution) do
      {:ok, steps}
    end
  end

  def list_logs(_parent, %{execution_id: id}, res) do
    with {:ok, %{execution: execution}} <- Executions.get_execution(Authz.to_id(id)),
         :ok <- Authz.authorize_execution(res, :view, execution) do
      {:ok, Executions.list_logs(execution.id)}
    end
  end

  # The agent step records its usage camelCased under the step's generic
  # `metadata` column (see Executions.put_step_metadata!/2); GraphQL exposes it
  # as a typed object, so the keys are mapped back to the schema's atoms here.
  def agent_usage(%{metadata: metadata}, _args, _res) when is_map(metadata) do
    case Map.get(metadata, "agent") do
      usage when is_map(usage) ->
        {:ok,
         %{
           model: usage["model"],
           input_tokens: usage["inputTokens"],
           output_tokens: usage["outputTokens"],
           cache_read_input_tokens: usage["cacheReadInputTokens"],
           cache_creation_input_tokens: usage["cacheCreationInputTokens"],
           estimated_cost_usd: usage["estimatedCostUsd"],
           stop_reason: usage["stopReason"],
           duration_ms: usage["durationMs"]
         }}

      _ ->
        {:ok, nil}
    end
  end

  def agent_usage(_parent, _args, _res), do: {:ok, nil}

  def stop(_parent, %{id: id}, res) do
    with {:ok, %{execution: execution}} <- Executions.get_execution(Authz.to_id(id)),
         :ok <- Authz.authorize_execution(res, :run, execution),
         {:ok, stopped} <- Executions.stop(execution.id) do
      {:ok, stopped}
    else
      {:error, :not_running} -> {:error, "Execution is not active"}
      other -> other
    end
  end
end
