defmodule CartographBackend.Steps.QueryDatabaseStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.DataSources
  alias CartographBackend.Vault

  @impl true
  def name, do: "queryDatabase"

  @impl true
  def execute(%StepContext{params: params, project_id: project_id} = ctx) do
    slug = Map.get(params, "source")
    query = Map.get(params, "query")
    result_key = Map.get(params, "result_key", "rows")
    bind_params = Map.get(params, "params", [])

    with {:slug, true} <- {:slug, is_binary(slug) and slug != ""},
         {:query, true} <- {:query, is_binary(query) and query != ""},
         {:read_only, :ok} <- {:read_only, ensure_read_only(query)},
         {:ds, {:ok, ds}} <- {:ds, DataSources.get_by_slug(slug)},
         {:access, true} <- {:access, authorized?(project_id, ds.id)},
         {:run, {:ok, rows}} <- {:run, run_query(ds, query, bind_params)} do
      StepContext.info(
        ctx,
        "queryDatabase: #{length(rows)} row(s) from '#{slug}' → state['#{result_key}']"
      )

      {:ok, StepContext.put_state(ctx, result_key, rows)}
    else
      {:slug, false} ->
        {:error, "queryDatabase: 'source' param is required"}

      {:query, false} ->
        {:error, "queryDatabase: 'query' param is required"}

      {:read_only, {:error, reason}} ->
        {:error, "queryDatabase: #{reason}"}

      {:ds, {:error, _}} ->
        {:error, "queryDatabase: data source '#{slug}' not found"}

      {:access, false} ->
        {:error, "queryDatabase: data source '#{slug}' is not accessible from this project"}

      {:run, {:error, reason}} ->
        {:error, "queryDatabase: #{reason}"}
    end
  end

  # A job outside any project is assigned no data source, so it reaches none.
  defp authorized?(nil, _ds_id), do: false
  defp authorized?(project_id, ds_id), do: DataSources.project_has_access?(project_id, ds_id)

  # ── Read-only enforcement ────────────────────────────────────────────────────

  # The authoritative guard is the read-only session opened in `run_query/3`:
  # the database itself refuses to write, including through a data-modifying
  # CTE (`WITH x AS (INSERT ...) SELECT ...`) that reads as a SELECT here.
  #
  # This check runs first anyway, so an obvious mistake comes back as a clear
  # step error instead of a driver error, and so a stacked statement is refused
  # even on a server configured to allow them. It is a filter, not the boundary
  # — do not add capabilities on the strength of it alone.
  @starts_read_only ~r/\A\s*(select|with)\b/i
  @line_comment ~r/--[^\n]*/
  @block_comment ~r/\/\*.*?\*\//s

  defp ensure_read_only(query) do
    stripped =
      query
      |> String.replace(@block_comment, " ")
      |> String.replace(@line_comment, " ")
      |> String.trim()

    cond do
      not Regex.match?(@starts_read_only, stripped) ->
        {:error, "only SELECT (or WITH ... SELECT) queries are allowed; use executeDatabase"}

      stacked_statement?(stripped) ->
        {:error, "only one statement is allowed per queryDatabase step"}

      true ->
        :ok
    end
  end

  # A semicolon is fine as a terminator, but not as a separator. Semicolons
  # inside string literals are left alone.
  defp stacked_statement?(sql) do
    sql
    |> String.replace(~r/'(?:[^']|'')*'/, "''")
    |> String.replace(~r/"(?:[^"]|"")*"/, "\"\"")
    |> String.trim_trailing()
    |> String.trim_trailing(";")
    |> String.contains?(";")
  end

  defp run_query(ds, query, bind_params) do
    password = Vault.decrypt(ds.password_encrypted)

    case ds.adapter do
      "postgres" ->
        opts = conn_opts(ds, password)

        # The connection is dedicated to this one query, so making the whole
        # session read-only is enough — and it is the database, not a regex,
        # that ends up enforcing it.
        with {:ok, pid} <- Postgrex.start_link(opts),
             {:ok, _} <-
               Postgrex.query(pid, "SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY", []),
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
             {:ok, _} <- MyXQL.query(pid, "SET SESSION TRANSACTION READ ONLY", []),
             {:ok, res} <- MyXQL.query(pid, query, bind_params) do
          GenServer.stop(pid, :normal)
          rows = Enum.map(res.rows, fn row -> Enum.zip(res.columns, row) |> Map.new() end)
          {:ok, rows}
        else
          {:error, reason} -> {:error, inspect(reason)}
        end

      other ->
        {:error, "unsupported adapter: #{other}"}
    end
  end

  defp conn_opts(ds, password) do
    [
      hostname: ds.host,
      port: ds.port,
      database: ds.database_name,
      username: ds.username,
      password: password || "",
      ssl: ds.ssl,
      timeout: 30_000
    ]
  end
end
