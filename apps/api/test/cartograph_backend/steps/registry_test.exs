defmodule CartographBackend.Steps.RegistryTest do
  use ExUnit.Case, async: true

  alias CartographBackend.Steps.Registry

  # This is a security test, not a bookkeeping one. `tool_capable/0` is the set
  # of steps a language model may invoke with params it wrote itself, so it must
  # never grow by accident — adding `tool_schema/0` to a step is a deliberate
  # decision that belongs in review. If this fails because you added a step,
  # re-read docs/design/ai-agent-tool-use.md before updating the list.
  test "the agent-callable safe set is exactly the read-only and pure steps" do
    assert Registry.tool_capable() == [
             "filter",
             "parseJson",
             "parseXml",
             "readDirectory",
             "transform",
             "validate"
           ]
  end

  test "steps with side effects are never agent-callable" do
    for name <-
          ~w(executeDatabase queryDatabase notify writeOutput writeJson writeXml agent delay) do
      refute name in Registry.tool_capable(),
             "#{name} must not be exposed to agents — see docs/design/ai-agent-tool-use.md"
    end
  end

  test "every agent-callable step is also a real registered step" do
    for name <- Registry.tool_capable() do
      assert {:ok, _module} = Registry.get(name)
      assert name in Registry.available_steps()
    end
  end

  test "tool_schema/1 returns a well-formed Anthropic tool definition" do
    for name <- Registry.tool_capable() do
      assert {:ok, schema} = Registry.tool_schema(name)
      assert is_binary(schema.description) and schema.description != ""
      assert schema.input_schema["type"] == "object"
      assert is_map(schema.input_schema["properties"])
      assert is_list(schema.input_schema["required"])
    end
  end

  test "tool_schema/1 refuses a step that did not opt in" do
    assert {:error, msg} = Registry.tool_schema("notify")
    assert msg =~ "not available to agents"
  end
end
