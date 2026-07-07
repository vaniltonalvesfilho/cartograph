defmodule CartographBackend.Steps.ExecuteDatabaseStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.DataSources
  alias CartographBackend.Vault

  @impl true
  def name, do: "executeDatabase"

  @impl true
  def execute(%StepContext{params: params, state: state, project_id: project_id} = ctx) do
    slug = Map.get(params, "source")
    query = Map.get(params, "query")
    rows_from = Map.get(params, "rows_from")
    columns = Map.get(params, "columns", [])
    bind_params = Map.get(params, "params", [])

    with {:slug, true} <- {:slug, is_binary(slug) and slug != ""},
         {:query, true} <- {:query, is_binary(query) and query != ""},
         {:ds, {:ok, ds}} <- {:ds, DataSources.get_by_slug(slug)},
         {:access, true} <- {:access, authorized?(project_id, ds.id)} do
      password = Vault.decrypt(ds.password_encrypted)
      rows_list = build_rows_list(rows_from, columns, bind_params, state)

      case run_execute(ds, password, query, rows_list) do
        {:ok, count} ->
          StepContext.info(ctx, "executeDatabase: #{count} row(s) affected on '#{slug}'")
          {:ok, ctx}

        {:error, reason} ->
          {:error, "executeDatabase: #{reason}"}
      end
    else
      {:slug, false} ->
        {:error, "executeDatabase: 'source' param is required"}

      {:query, false} ->
        {:error, "executeDatabase: 'query' param is required"}

      {:ds, {:error, _}} ->
        {:error, "executeDatabase: data source '#{slug}' not found"}

      {:access, false} ->
        {:error, "executeDatabase: data source '#{slug}' is not accessible from this project"}
    end
  end

  defp authorized?(nil, _ds_id), do: true
  defp authorized?(project_id, ds_id), do: DataSources.project_has_access?(project_id, ds_id)

  defp build_rows_list(nil, _columns, bind_params, _state), do: [bind_params]

  defp build_rows_list(rows_from, columns, _bind_params, state) do
    col_list = normalize_columns(columns)
    rows = Map.get(state, rows_from, [])

    Enum.map(rows, fn row ->
      if col_list == [] do
        Map.values(row)
      else
        # Row keys may be strings or atoms depending on the producing step;
        # compare by string form. Never String.to_atom on DSL input — atoms
        # are not garbage collected, so user input could exhaust the atom table.
        row = Map.new(row, fn {k, v} -> {to_string(k), v} end)
        Enum.map(col_list, &Map.get(row, &1))
      end
    end)
  end

  # Accepts columns as a CSV string ("a,b,c"), a JSON array string, or a list
  defp normalize_columns([]), do: []
  defp normalize_columns(list) when is_list(list), do: Enum.map(list, &to_string/1)

  defp normalize_columns(str) when is_binary(str) do
    str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp run_execute(ds, password, query, rows_list) do
    case ds.adapter do
      "postgres" -> exec_postgres(ds, password, query, rows_list)
      "mysql" -> exec_mysql(ds, password, query, rows_list)
      other -> {:error, "unsupported adapter: #{other}"}
    end
  end

  defp exec_postgres(ds, password, query, rows_list) do
    opts = [
      hostname: ds.host,
      port: ds.port,
      database: ds.database_name,
      username: ds.username,
      password: password || "",
      ssl: ds.ssl,
      timeout: 30_000
    ]

    case Postgrex.start_link(opts) do
      {:error, reason} ->
        {:error, inspect(reason)}

      {:ok, pid} ->
        try do
          total =
            Enum.reduce(rows_list, 0, fn row_params, acc ->
              case Postgrex.query(pid, query, row_params) do
                {:ok, res} -> acc + res.num_rows
                {:error, reason} -> throw({:pg_error, inspect(reason)})
              end
            end)

          GenServer.stop(pid, :normal)
          {:ok, total}
        catch
          {:pg_error, reason} ->
            GenServer.stop(pid, :normal)
            {:error, reason}
        end
    end
  end

  defp exec_mysql(ds, password, query, rows_list) do
    opts = [
      hostname: ds.host,
      port: ds.port,
      database: ds.database_name,
      username: ds.username,
      password: password || "",
      ssl: ds.ssl,
      timeout: 30_000
    ]

    case MyXQL.start_link(opts) do
      {:error, reason} ->
        {:error, inspect(reason)}

      {:ok, pid} ->
        try do
          total =
            Enum.reduce(rows_list, 0, fn row_params, acc ->
              case MyXQL.query(pid, query, row_params) do
                {:ok, res} -> acc + res.num_rows
                {:error, reason} -> throw({:mysql_error, inspect(reason)})
              end
            end)

          GenServer.stop(pid, :normal)
          {:ok, total}
        catch
          {:mysql_error, reason} ->
            GenServer.stop(pid, :normal)
            {:error, reason}
        end
    end
  end
end
