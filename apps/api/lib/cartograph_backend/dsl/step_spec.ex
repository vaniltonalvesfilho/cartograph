defmodule CartographBackend.Dsl.StepSpec do
  # `flow_id` is the structural path of the node in `Dsl.Flow`'s tree ("0",
  # "1/t0", "2/j0", …), stamped by the Expander so the runtime can persist the
  # step's provenance (step_execution.flow_node_id). Nil until expansion.
  @type t :: %__MODULE__{name: String.t(), params: map(), flow_id: String.t() | nil}
  defstruct [:name, :params, :flow_id]
end
