defmodule CartographBackend.Steps.QueryDatabaseStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.DataSources
  alias CartographBackend.Vault

  @impl true
  def name, do: "queryDatabase"

  @impl true
  def execute(%StepContext{params: params, project_id: project_id} = ctx) do
    slug        = Map.get(params, "source")
    query       = Map.get(params, "query")
    result_key  = Map.get(params, "result_key", "rows")
    bind_params = Map.get(params, "params", [])

    with {:slug,   true}       <- {:slug,   is_binary(slug) and slug != ""},
         {:query,  true}       <- {:query,  is_binary(query) and query != ""},
         {:ds,     {:ok, ds}}  <- {:ds,     DataSources.get_by_slug(slug)},
         {:access, true}       <- {:access, authorized?(project_id, ds.id)},
         {:run,    {:ok, rows}} <- {:run,   run_query(ds, query, bind_params)} do
      StepContext.info(ctx, "queryDatabase: #{length(rows)} row(s) from '#{slug}' → state['#{result_key}']")
      {:ok, StepContext.put_state(ctx, result_key, rows)}
    else
      {:slug,   false}           -> {:error, "queryDatabase: 'source' param is required"}
      {:query,  false}           -> {:error, "queryDatabase: 'query' param is required"}
      {:ds,     {:error, _}}     -> {:error, "queryDatabase: data source '#{slug}' not found"}
      {:access, false}           -> {:error, "queryDatabase: data source '#{slug}' is not accessible from this project"}
      {:run,    {:error, reason}} -> {:error, "queryDatabase: #{reason}"}
    end
  end

  defp authorized?(nil, _ds_id), do: true
  defp authorized?(project_id, ds_id), do: DataSources.project_has_access?(project_id, ds_id)

  defp run_query(ds, query, bind_params) do
    password = Vault.decrypt(ds.password_encrypted)

    case ds.adapter do
      "postgres" ->
        opts = conn_opts(ds, password)
        with {:ok, pid} <- Postgrex.start_link(opts),
             {:ok, res} <- Postgrex.query(pid, query, bind_params) do
          GenServer.stop(pid, :normal)
          rows = Enum.map(res.rows, fn row -> Enum.zip(res.columns, row) |> Map.new() end)
          {:ok, rows}
        else
          {:error, reason} -> {:error, inspect(reason)}
        end

      "mysql" ->
        opts = conn_opts(ds, password)
        with {:ok, pid} <- MyXQL.start_link(opts),
             {:ok, res} <- MyXQL.query(pid, query, bind_params) do
          GenServer.stop(pid, :normal)
          rows = Enum.map(res.rows, fn row -> Enum.zip(res.columns, row) |> Map.new() end)
          {:ok, rows}
        else
          {:error, reason} -> {:error, inspect(reason)}
        end

      other -> {:error, "unsupported adapter: #{other}"}
    end
  end

  defp conn_opts(ds, password) do
    [hostname: ds.host, port: ds.port, database: ds.database_name,
     username: ds.username, password: password || "", ssl: ds.ssl, timeout: 30_000]
  end
end
