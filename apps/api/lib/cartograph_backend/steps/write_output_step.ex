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

    # A pipeline with a `transform` step leaves its output under "transformed";
    # without one, writeOutput acts as a plain file transfer of the current
    # "files" list (readDirectory/filter output).
    case StepContext.get_state(ctx, "transformed") do
      nil -> copy_files(ctx, dir)
      transformed -> write_transformed(ctx, dir, transformed)
    end
  end

  defp write_transformed(ctx, dir, transformed) do
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

    finish(ctx, results, map_size(transformed))
  end

  defp copy_files(ctx, dir) do
    files = StepContext.get_state(ctx, "files", [])
    StepContext.info(ctx, "No transformed content in state; copying #{length(files)} input file(s)")

    results =
      Enum.map(files, fn file ->
        target = Path.join(dir, Path.basename(file))

        with {:ok, source} <- SafePath.resolve(file, ctx.project_id),
             :ok <- File.cp(source, target) do
          StepContext.info(ctx, "  copied #{Path.basename(target)}")
          :ok
        else
          {:error, reason} ->
            {:error, "Failed to copy #{Path.basename(file)}: #{reason}"}
        end
      end)

    finish(ctx, results, length(files))
  end

  defp finish(ctx, results, count) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        StepContext.info(ctx, "Done. #{count} file(s) written.")
        {:ok, ctx}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
