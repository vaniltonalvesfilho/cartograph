defmodule CartographBackendWeb.AgentUsageExposureTest do
  # The agent step records usage under the step's generic `metadata` column;
  # REST returns that map as `agentUsage` and GraphQL re-types it. Both views
  # must stay mirrors of each other, and null for non-agent steps.
  use CartographBackend.DataCase, async: true

  alias CartographBackend.Executions
  alias CartographBackend.Executions.StepExecution
  alias CartographBackendWeb.Graphql.Resolvers
  alias CartographBackendWeb.Serializers

  @execution_id 888_888

  @usage %{
    "model" => "claude-opus-4-8",
    "inputTokens" => 1234,
    "outputTokens" => 456,
    "cacheReadInputTokens" => 0,
    "estimatedCostUsd" => 0.0175,
    "stopReason" => "end_turn",
    "durationMs" => 8342
  }

  defp step_with_usage do
    step = Executions.create_step!(@execution_id, "agent", 1)
    Executions.put_step_metadata!(step.id, %{"agent" => @usage})
    Repo.get!(StepExecution, step.id)
  end

  test "REST exposes the recorded usage verbatim as agentUsage" do
    assert Serializers.step_execution(step_with_usage()).agentUsage == @usage
  end

  test "REST reports agentUsage as null for a step that recorded nothing" do
    step = Executions.create_step!(@execution_id, "transform", 2)
    assert Serializers.step_execution(step).agentUsage == nil
  end

  test "GraphQL re-types the camelCase metadata into the agent_usage object" do
    assert {:ok, usage} = Resolvers.Executions.agent_usage(step_with_usage(), %{}, %{})

    assert usage.model == "claude-opus-4-8"
    assert usage.input_tokens == 1234
    assert usage.output_tokens == 456
    assert usage.cache_read_input_tokens == 0
    assert usage.estimated_cost_usd == 0.0175
    assert usage.stop_reason == "end_turn"
    assert usage.duration_ms == 8342
    # Absent in the metadata (no cache write) → null, not a crash.
    assert usage.cache_creation_input_tokens == nil
  end

  test "GraphQL resolves agent_usage to null for a step that recorded nothing" do
    step = Executions.create_step!(@execution_id, "transform", 2)
    assert {:ok, nil} = Resolvers.Executions.agent_usage(step, %{}, %{})
  end
end
