defmodule CartographBackend.Steps.TransformStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Steps.SafePath

  @impl true
  def name, do: "transform"

  # Agent-callable: reads the files already in state['files'] and writes the
  # results to state['transformed']. Nothing is written back to disk, and the
  # `operation` enum is closed — an unknown op fails the step rather than
  # reaching any dynamic dispatch.
  @impl true
  def tool_schema do
    %{
      description:
        "Read every file in state['files'] and apply a text operation, writing the results " <>
          "to state['transformed'] as a map of filename to transformed content. " <>
          "Requires state['files'] to be populated first (see readDirectory).",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "operation" => %{
            "type" => "string",
            "enum" => ["uppercase", "lowercase", "reverse", "lineCount"],
            "description" =>
              "The transform to apply. 'lineCount' replaces the content with a line tally " <>
                "rather than transforming it. Defaults to 'uppercase'."
          }
        },
        "required" => []
      }
    }
  end

  @impl true
  def execute(%StepContext{params: params} = ctx) do
    op = Map.get(params, "operation", "uppercase")
    files = StepContext.get_state(ctx, "files", [])
    StepContext.info(ctx, "Applying transform '#{op}' to #{length(files)} file(s)")

    result =
      Enum.reduce_while(files, {:ok, %{}}, fn file, {:ok, acc} ->
        if StepContext.cancelled?(ctx) do
          StepContext.info(ctx, "Cancellation requested; stopping transform loop")
          {:halt, {:ok, acc}}
        else
          case apply_transform(file, op, ctx) do
            {:ok, {filename, content}} ->
              # Small delay so live-log streaming is visible in the dashboard
              Process.sleep(300)
              {:cont, {:ok, Map.put(acc, filename, content)}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end
      end)

    case result do
      {:ok, transformed} -> {:ok, StepContext.put_state(ctx, "transformed", transformed)}
      {:error, reason} -> {:error, reason}
    end
  end

  @sobelow_skip ["Traversal.FileModule"]
  defp apply_transform(file, op, ctx) do
    # The path comes from state["files"], not from a param — and any step that
    # writes to state can put anything there (parseJson takes a model-chosen
    # `result_key`). Confining here, as writeOutput already does for its
    # sources, is what keeps a poisoned state from turning into an arbitrary
    # file read. See docs/design/ai-agent-tool-use.md §1.
    with {:ok, path} <- SafePath.resolve(file, ctx.project_id),
         {:ok, content} <- File.read(path) do
      apply_op(file, content, op, ctx)
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "Failed to read #{Path.basename(file)}: #{reason}"}
    end
  end

  defp apply_op(file, content, op, ctx) do
    case transform(content, op) do
      {:error, reason} ->
        {:error, reason}

      {:ok, result} ->
        StepContext.info(
          ctx,
          "  transformed #{Path.basename(file)} (#{byte_size(content)} -> #{byte_size(result)} chars)"
        )

        {:ok, {Path.basename(file), result}}
    end
  end

  defp transform(content, "uppercase"), do: {:ok, String.upcase(content)}
  defp transform(content, "lowercase"), do: {:ok, String.downcase(content)}
  defp transform(content, "reverse"), do: {:ok, String.reverse(content)}

  defp transform(content, "lineCount") do
    count = content |> String.split("\n") |> length()
    {:ok, "lines: #{count}"}
  end

  defp transform(_content, op), do: {:error, "Unknown operation: #{op}"}
end
