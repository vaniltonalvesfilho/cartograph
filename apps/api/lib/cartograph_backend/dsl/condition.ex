defmodule CartographBackend.Dsl.Condition do
  @moduledoc "Evaluates condition expressions against runtime state."

  @type expr :: CartographBackend.Dsl.IfNode.expr()

  @spec eval(expr(), map()) :: any()
  def eval({:literal, v}, _state), do: v
  def eval({:state_get, k}, state), do: Map.get(state, k)

  def eval({:compare, :eq, l, r}, s), do: eval(l, s) == eval(r, s)
  def eval({:compare, :neq, l, r}, s), do: eval(l, s) != eval(r, s)
  def eval({:compare, :gt, l, r}, s), do: eval(l, s) > eval(r, s)
  def eval({:compare, :lt, l, r}, s), do: eval(l, s) < eval(r, s)
  def eval({:compare, :gte, l, r}, s), do: eval(l, s) >= eval(r, s)
  def eval({:compare, :lte, l, r}, s), do: eval(l, s) <= eval(r, s)

  def eval({:logical, :and, [a, b]}, s), do: truthy?(eval(a, s)) and truthy?(eval(b, s))
  def eval({:logical, :or, [a, b]}, s), do: truthy?(eval(a, s)) or truthy?(eval(b, s))
  def eval({:logical, :not, expr}, s), do: not truthy?(eval(expr, s))

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_), do: true
end
