defmodule CartographBackend.Steps.ReadDirectoryStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Steps.SafePath

  @impl true
  def name, do: "readDirectory"

  # Agent-callable: read-only, and `path` is confined to the executing
  # project's data root by SafePath.resolve/2 — the same gate a job author's
  # literal path goes through.
  @impl true
  def tool_schema do
    %{
      description:
        "List the regular files in a directory, writing their paths to state['files']. " <>
          "Call this first when you need to know what files exist before filtering, " <>
          "parsing or transforming them.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" =>
              "Directory relative to the project's data root, e.g. 'data/inbox'. " <>
                "Defaults to 'data/inbox'. Paths outside the project are rejected."
          }
        },
        "required" => []
      }
    }
  end

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
