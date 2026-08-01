defmodule CartographBackend.Steps.FilterFilesStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext

  @impl true
  def name, do: "filter"

  # Agent-callable: pure. Reads state['files'] and narrows it; touches nothing
  # outside the shared state.
  @impl true
  def tool_schema do
    %{
      description:
        "Narrow state['files'] to the files with a given extension. " <>
          "Requires state['files'] to be populated first (see readDirectory). " <>
          "This replaces state['files'] with the filtered list.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "extension" => %{
            "type" => "string",
            "description" =>
              "Extension without the leading dot, e.g. 'json'. Case-insensitive. Defaults to 'txt'."
          }
        },
        "required" => []
      }
    }
  end

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
