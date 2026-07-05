defmodule CartographBackend.Steps.ReadDirectoryStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Steps.SafePath

  @impl true
  def name, do: "readDirectory"

  @impl true
  def execute(%StepContext{params: params} = ctx) do
    path = Map.get(params, "path", "data/inbox")

    case SafePath.resolve(path, ctx.project_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, dir} ->
        StepContext.info(ctx, "Reading directory: #{dir}")

        case File.ls(dir) do
          {:error, _reason} ->
            {:error, "Directory does not exist: #{dir}"}

          {:ok, entries} ->
            files =
              entries
              |> Enum.filter(&File.regular?(Path.join(dir, &1)))
              |> Enum.sort()
              |> Enum.map(&Path.join(dir, &1))

            StepContext.info(ctx, "Found #{length(files)} file(s)")
            Enum.each(files, fn f -> StepContext.info(ctx, "  - #{Path.basename(f)}") end)

            {:ok, StepContext.put_state(ctx, "files", files)}
        end
    end
  end
end
