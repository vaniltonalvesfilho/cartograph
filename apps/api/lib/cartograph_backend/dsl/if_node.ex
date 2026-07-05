defmodule CartographBackend.Dsl.IfNode do
  @type expr ::
          {:literal, any()}
          | {:state_get, String.t()}
          | {:compare, :eq | :neq | :gt | :lt | :gte | :lte, expr(), expr()}
          | {:logical, :and | :or, [expr()]}
          | {:logical, :not, expr()}

  @type dsl_node :: CartographBackend.Dsl.StepSpec.t() | __MODULE__.t()

  @type t :: %__MODULE__{
          condition: expr(),
          then_steps: [dsl_node()],
          else_steps: [dsl_node()]
        }

  defstruct [:condition, :then_steps, :else_steps]
end
