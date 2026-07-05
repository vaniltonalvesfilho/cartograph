defmodule CartographBackend.Dsl.TaskDsl do
  @type dsl_node :: CartographBackend.Dsl.StepSpec.t() | CartographBackend.Dsl.IfNode.t()

  @type t :: %__MODULE__{
          task_name: String.t(),
          steps: [dsl_node()]
        }
  defstruct [:task_name, :steps]
end
