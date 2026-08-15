defmodule CartographBackend.Steps.ParseJsonStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Steps.SafePath

  @impl true
  def name, do: "parseJson"

  # Agent-callable: reads one file and writes the decoded value to state. Both
  # the direct `path` and the state-sourced `file_key` go through
  # SafePath.resolve/2, so a model-written path cannot escape the project.
  @impl true
  def tool_schema do
    %{
      description:
        "Read a JSON file and put the decoded value into the shared state. " <>
          "Use this to inspect the contents of a file you found with readDirectory. " <>
          "Give either 'path' directly, or 'file_key' naming a state key that holds the path.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" =>
              "File relative to the project's data root. Paths outside the project are rejected."
          },
          "file_key" => %{
            "type" => "string",
            "description" =>
              "State key holding the path, used when 'path' is absent. Defaults to 'current_file'."
          },
          "root_path" => %{
            "type" => "string",
            "description" =>
              "Optional dot path into the decoded document, e.g. 'data.items', to store just that part."
          },
          "result_key" => %{
            "type" => "string",
            "description" => "State key to write the result to. Defaults to 'rows'."
          }
        },
        "required" => []
      }
    }
  end

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
