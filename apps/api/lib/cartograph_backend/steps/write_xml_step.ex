defmodule CartographBackend.Steps.WriteXmlStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Steps.SafePath

  @impl true
  def name, do: "writeXml"

  @impl true
  def execute(%StepContext{params: params} = ctx) do
    data_key     = Map.get(params, "data_key", "rows")
    raw_path     = Map.get(params, "path")
    root_element = Map.get(params, "root_element", "rows")
    row_element  = Map.get(params, "row_element", "row")

    rows = StepContext.get_state(ctx, data_key, [])

    with {:path, true}             <- {:path, is_binary(raw_path) and raw_path != ""},
         {:safe, {:ok, full_path}} <- {:safe, SafePath.resolve(raw_path, ctx.project_id)} do
      xml = build_xml(rows, root_element, row_element)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, xml)
      StepContext.info(ctx, "writeXml: wrote #{length(rows)} <#{row_element}> element(s) to #{full_path}")
      {:ok, ctx}
    else
      {:path, false}            -> {:error, "writeXml: 'path' param is required"}
      {:safe, {:error, reason}} -> {:error, "writeXml: #{reason}"}
    end
  end

  defp build_xml(rows, root_el, row_el) do
    rows_xml =
      Enum.map_join(rows, "\n", fn row ->
        fields =
          Enum.map_join(row, "\n", fn {k, v} ->
            "    <#{k}>#{escape(to_string(v))}</#{k}>"
          end)
        "  <#{row_el}>\n#{fields}\n  </#{row_el}>"
      end)

    ~s(<?xml version="1.0" encoding="UTF-8"?>\n<#{root_el}>\n#{rows_xml}\n</#{root_el}>)
  end

  defp escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
