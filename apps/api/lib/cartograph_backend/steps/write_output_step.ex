defmodule CartographBackend.Steps.WriteOutputStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Steps.SafePath

  @impl true
  def name, do: "writeOutput"

  @impl true
  def execute(%StepContext{params: params} = ctx) do
    path = Map.get(params, "path", "data/outbox")

    with {:ok, dir} <- SafePath.resolve(path, ctx.project_id) do
      do_write(ctx, dir)
    end
  end

  defp do_write(ctx, dir) do
    File.mkdir_p!(dir)
    StepContext.info(ctx, "Writing output to: #{dir}")

    transformed = StepContext.get_state(ctx, "transformed", %{})

    results =
      Enum.map(transformed, fn {filename, content} ->
        target = Path.join(dir, "processed_#{Path.basename(filename)}")
        case File.write(target, content) do
          :ok ->
            StepContext.info(ctx, "  wrote #{Path.basename(target)}")
            :ok
          {:error, reason} ->
            {:error, "Failed to write #{target}: #{reason}"}
        end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        StepContext.info(ctx, "Done. #{map_size(transformed)} file(s) written.")
        {:ok, ctx}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
