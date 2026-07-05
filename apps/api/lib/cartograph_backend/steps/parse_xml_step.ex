defmodule CartographBackend.Steps.ParseXmlStep do
  @behaviour CartographBackend.Steps.Step

  import SweetXml, only: [xpath: 2, sigil_x: 2]
  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Steps.SafePath

  @impl true
  def name, do: "parseXml"

  @impl true
  def execute(%StepContext{params: params} = ctx) do
    result_key   = Map.get(params, "result_key", "rows")
    root_element = Map.get(params, "root_element")
    direct_path  = Map.get(params, "path")
    file_key     = Map.get(params, "file_key", "current_file")
    raw_path     = direct_path || StepContext.get_state(ctx, file_key)

    with {:path, true}             <- {:path, is_binary(raw_path) and raw_path != ""},
         {:root, true}             <- {:root, is_binary(root_element) and root_element != ""},
         {:safe, {:ok, full_path}} <- {:safe, SafePath.resolve(raw_path, ctx.project_id)},
         {:read, {:ok, content}}   <- {:read, File.read(full_path)},
         {:parse, {:ok, rows}}     <- {:parse, do_parse(content, root_element)} do
      StepContext.info(ctx, "parseXml: #{length(rows)} <#{root_element}> element(s) from #{Path.basename(full_path)} → state['#{result_key}']")
      {:ok, StepContext.put_state(ctx, result_key, rows)}
    else
      {:path,  false}            -> {:error, "parseXml: 'path' or 'file_key' pointing to a file is required"}
      {:root,  false}            -> {:error, "parseXml: 'root_element' param is required"}
      {:safe,  {:error, reason}} -> {:error, "parseXml: #{reason}"}
      {:read,  {:error, reason}} -> {:error, "parseXml: could not read file: #{inspect(reason)}"}
      {:parse, {:error, reason}} -> {:error, "parseXml: #{reason}"}
    end
  end

  defp do_parse(content, root_element) do
    try do
      rows =
        content
        |> xpath(~x"//#{root_element}"l)
        |> Enum.map(fn node ->
          # Each node is an xmerl xmlElement; child elements have their tag as atom in position 2
          node
          |> xpath(~x"*"l)
          |> Enum.reduce(%{}, fn child, acc ->
            tag   = elem(child, 1) |> to_string()
            value = child |> xpath(~x"text()"s)
            Map.put(acc, tag, value)
          end)
        end)
      {:ok, rows}
    rescue
      e -> {:error, "XML parse error: #{Exception.message(e)}"}
    end
  end
end
