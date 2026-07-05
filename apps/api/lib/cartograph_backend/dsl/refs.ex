defmodule CartographBackend.Dsl.Refs do
  @moduledoc """
  Extracts the job codes referenced via `use`/`job` from a DSL source, without
  resolving or authorizing them (callers decide what a ref may point to —
  `RefResolver` remains the authority for resolution).

  Walks the parsed AST including if/else branches. A DSL that fails to parse
  simply has no refs — this module is for read-only views (e.g. the cross-job
  graph), never for validation.
  """

  alias CartographBackend.Dsl.{IfNode, Parser, StepSpec}

  @job_meta "__job__"

  @doc "Referenced job codes in source order, deduplicated."
  @spec extract(String.t() | nil) :: [String.t()]
  def extract(dsl) do
    case Parser.parse(dsl) do
      {:ok, %{steps: steps}} -> steps |> collect([]) |> Enum.reverse() |> Enum.uniq()
      {:error, _} -> []
    end
  end

  defp collect(nodes, acc), do: Enum.reduce(nodes, acc, &collect_node/2)

  defp collect_node(%StepSpec{name: @job_meta, params: %{"ref" => ref}}, acc), do: [ref | acc]
  defp collect_node(%StepSpec{}, acc), do: acc

  defp collect_node(%IfNode{then_steps: then_steps, else_steps: else_steps}, acc),
    do: collect(else_steps, collect(then_steps, acc))
end
