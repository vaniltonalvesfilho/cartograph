defmodule CartographBackend.Steps.FilterFilesStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext

  @impl true
  def name, do: "filter"

  @impl true
  def execute(%StepContext{params: params} = ctx) do
    ext = "." <> String.downcase(Map.get(params, "extension", "txt"))
    files = StepContext.get_state(ctx, "files", [])

    filtered =
      Enum.filter(files, fn f ->
        f |> Path.basename() |> String.downcase() |> String.ends_with?(ext)
      end)

    StepContext.info(
      ctx,
      "Filtering by extension '#{ext}': #{length(filtered)} of #{length(files)} file(s) matched"
    )

    {:ok, StepContext.put_state(ctx, "files", filtered)}
  end
end
