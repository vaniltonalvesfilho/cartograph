defmodule CartographBackend.Steps.ParseJsonStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Steps.SafePath

  @impl true
  def name, do: "parseJson"

  @impl true
  def execute(%StepContext{params: params} = ctx) do
    result_key = Map.get(params, "result_key", "rows")
    root_path = Map.get(params, "root_path")
    direct_path = Map.get(params, "path")
    file_key = Map.get(params, "file_key", "current_file")
    raw_path = direct_path || StepContext.get_state(ctx, file_key)

    with {:path, true} <- {:path, is_binary(raw_path) and raw_path != ""},
         {:safe, {:ok, full_path}} <- {:safe, SafePath.resolve(raw_path, ctx.project_id)},
         {:read, {:ok, content}} <- {:read, File.read(full_path)},
         {:decode, {:ok, data}} <- {:decode, Jason.decode(content)} do
      extracted = if root_path, do: dig(data, root_path), else: data

      StepContext.info(
        ctx,
        "parseJson: parsed #{Path.basename(raw_path)} → state['#{result_key}']"
      )

      {:ok, StepContext.put_state(ctx, result_key, extracted)}
    else
      {:path, false} -> {:error, "parseJson: 'path' or 'file_key' is required"}
      {:safe, {:error, reason}} -> {:error, "parseJson: #{reason}"}
      {:read, {:error, reason}} -> {:error, "parseJson: could not read file: #{inspect(reason)}"}
      {:decode, {:error, reason}} -> {:error, "parseJson: JSON decode error: #{inspect(reason)}"}
    end
  end

  defp dig(data, dot_path) do
    dot_path
    |> String.split(".")
    |> Enum.reduce(data, fn key, acc ->
      case acc do
        map when is_map(map) -> Map.get(map, key)
        _ -> nil
      end
    end)
  end
end
