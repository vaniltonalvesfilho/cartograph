defmodule CartographBackend.Steps.WriteJsonStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.{Provenance, StepContext}
  alias CartographBackend.Steps.SafePath

  @impl true
  def name, do: "writeJson"

  @impl true
  @sobelow_skip ["Traversal.FileModule"]
  def execute(%StepContext{params: params} = ctx) do
    data_key = Map.get(params, "data_key", "rows")
    raw_path = Map.get(params, "path")
    pretty = Map.get(params, "pretty", false)

    data = StepContext.get_state(ctx, data_key, [])

    with {:path, true} <- {:path, is_binary(raw_path) and raw_path != ""},
         {:agent, :ok} <- {:agent, Provenance.guard_consumption(ctx, data_key, name())},
         {:safe, {:ok, full_path}} <- {:safe, SafePath.resolve(raw_path, ctx.project_id)} do
      json = if pretty, do: Jason.encode!(data, pretty: true), else: Jason.encode!(data)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, json)
      StepContext.info(ctx, "writeJson: wrote to #{full_path}")
      {:ok, ctx}
    else
      {:path, false} -> {:error, "writeJson: 'path' param is required"}
      {:agent, {:error, reason}} -> {:error, reason}
      {:safe, {:error, reason}} -> {:error, "writeJson: #{reason}"}
    end
  end
end
