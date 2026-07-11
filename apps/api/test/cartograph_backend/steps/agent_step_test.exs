defmodule CartographBackend.Steps.AgentStepTest do
  # NOT async: registers the test pid / fake response via the app env.
  use CartographBackend.DataCase, async: false

  alias CartographBackend.{Agents, Executions}
  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Executions.StepExecution
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Steps.AgentStep

  @api_key "sk-ant-api03-test-0123456789"
  @execution_id 999_999

  setup do
    Application.put_env(:cartograph_backend, :anthropic_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:cartograph_backend, :anthropic_test_pid)
      Application.delete_env(:cartograph_backend, :anthropic_fake_response)
    end)

    group = %Group{} |> Group.changeset(%{name: "infra"}) |> Repo.insert!()

    project =
      %Project{} |> Project.changeset(%{name: "Linux", group_id: group.id}) |> Repo.insert!()

    {:ok, credential} =
      Agents.create(%{"name" => "prod key", "api_key" => @api_key, "project_id" => project.id})

    %{project: project, credential: credential}
  end

  # Builds a context backed by a real step_execution row, so the step can
  # persist usage metadata the way it does under the interpreter.
  defp ctx(params, project_id, opts \\ []) do
    step = Executions.create_step!(@execution_id, "agent", 1)

    %StepContext{
      params: params,
      state: Keyword.get(opts, :state, %{}),
      execution_id: @execution_id,
      step_execution_id: step.id,
      project_id: project_id,
      agent_token_budget: Keyword.get(opts, :budget),
      log: fn _level, _msg -> :ok end,
      cancelled?: fn -> false end
    }
  end

  defp metadata(ctx), do: Repo.get!(StepExecution, ctx.step_execution_id).metadata

  test "success: trimmed response text lands in state and usage is recorded", %{
    project: p,
    credential: c
  } do
    Application.put_env(
      :cartograph_backend,
      :anthropic_fake_response,
      {:ok,
       %{
         "stop_reason" => "end_turn",
         "content" => [
           %{"type" => "text", "text" => "  APPROVE"},
           %{"type" => "text", "text" => "D  "}
         ],
         "usage" => %{"input_tokens" => 100, "output_tokens" => 50}
       }}
    )

    ctx = ctx(%{"secret" => c.code, "prompt" => "Review this."}, p.id)
    assert {:ok, new_ctx} = AgentStep.execute(ctx)

    # Defaults: model, maxTokens, single user message; key decrypted at call time.
    assert_receive {:anthropic_create_message, @api_key, body}
    assert body["model"] == "claude-opus-4-8"
    assert body["max_tokens"] == 4096
    assert body["messages"] == [%{"role" => "user", "content" => "Review this."}]
    refute Map.has_key?(body, "system")
    refute Map.has_key?(body, "temperature")

    # Text blocks concatenated and trimmed, written to the default output key.
    assert StepContext.get_state(new_ctx, "agent_result") == "APPROVED"

    # Budget counter accumulated in the reserved state key.
    assert StepContext.get_state(new_ctx, "__agent_tokens__") == 150

    # Usage persisted on the step's metadata (opus 4-8: $5/$25 per MTok).
    meta = metadata(ctx)["agent"]
    assert meta["model"] == "claude-opus-4-8"
    assert meta["inputTokens"] == 100
    assert meta["outputTokens"] == 50
    assert meta["stopReason"] == "end_turn"
    assert_in_delta meta["estimatedCostUsd"], 0.00175, 1.0e-9
    assert is_integer(meta["durationMs"])
  end

  test "optional params are forwarded: system, temperature, model, output, maxTokens", %{
    project: p,
    credential: c
  } do
    params = %{
      "secret" => c.code,
      "prompt" => "Hi",
      "system" => "Be terse, {{tone}}.",
      "model" => "claude-haiku-4-5",
      "temperature" => 0.7,
      "maxTokens" => 512,
      "output" => "answer"
    }

    ctx = ctx(params, p.id, state: %{"tone" => "always"})
    assert {:ok, new_ctx} = AgentStep.execute(ctx)

    assert_receive {:anthropic_create_message, @api_key, body}
    assert body["system"] == "Be terse, always."
    assert body["temperature"] == 0.7
    assert body["model"] == "claude-haiku-4-5"
    assert body["max_tokens"] == 512

    assert StepContext.get_state(new_ctx, "answer") == "Fake agent answer."
  end

  test "prompt interpolation inserts binaries verbatim and JSON-encodes the rest", %{
    project: p,
    credential: c
  } do
    state = %{"draft" => "A draft about cats.", "count" => 3, "tags" => ["a", "b"]}
    params = %{"secret" => c.code, "prompt" => "Refine: {{ draft }} n={{count}} tags={{tags}}"}

    assert {:ok, _} = AgentStep.execute(ctx(params, p.id, state: state))

    assert_receive {:anthropic_create_message, _key, body}

    assert body["messages"] == [
             %{
               "role" => "user",
               "content" => ~s(Refine: A draft about cats. n=3 tags=["a","b"])
             }
           ]
  end

  test "a missing state key fails the step before any API call", %{project: p, credential: c} do
    params = %{"secret" => c.code, "prompt" => "Refine: {{draft}}"}

    assert {:error, msg} = AgentStep.execute(ctx(params, p.id))
    assert msg == "agent: prompt references unknown state key 'draft'"
    refute_receive {:anthropic_create_message, _, _}
  end

  test "missing secret and missing prompt fail before any lookup", %{project: p, credential: c} do
    assert {:error, msg} = AgentStep.execute(ctx(%{"prompt" => "Hi"}, p.id))
    assert msg =~ "'secret' param is required"

    assert {:error, msg} = AgentStep.execute(ctx(%{"secret" => c.code}, p.id))
    assert msg =~ "'prompt' param is required"

    refute_receive {:anthropic_create_message, _, _}
  end

  test "maxTokens is validated to 1..16000", %{project: p, credential: c} do
    for bad <- [0, 16_001, "many"] do
      params = %{"secret" => c.code, "prompt" => "Hi", "maxTokens" => bad}
      assert {:error, msg} = AgentStep.execute(ctx(params, p.id))
      assert msg =~ "'maxTokens' must be an integer between 1 and 16000"
    end

    refute_receive {:anthropic_create_message, _, _}
  end

  test "unknown code and another project's credential fail with the same message", %{
    project: p,
    credential: c
  } do
    assert {:error, unknown} =
             AgentStep.execute(ctx(%{"secret" => "anthropic-00000000", "prompt" => "Hi"}, p.id))

    other = %Project{} |> Project.changeset(%{name: "Outro", group_id: nil}) |> Repo.insert!()

    assert {:error, foreign} =
             AgentStep.execute(ctx(%{"secret" => c.code, "prompt" => "Hi"}, other.id))

    assert unknown == String.replace(foreign, c.code, "anthropic-00000000")
    refute_receive {:anthropic_create_message, _, _}
  end

  test "an exhausted budget fails without calling the API", %{project: p, credential: c} do
    # Job-level budget from the task definition…
    params = %{"secret" => c.code, "prompt" => "Hi"}
    ctx = ctx(params, p.id, budget: 100, state: %{"__agent_tokens__" => 100})

    assert {:error, msg} = AgentStep.execute(ctx)
    assert msg == "agent: execution token budget exhausted (100/100 tokens)"

    # …and the server default (200k) when the job has none.
    ctx = ctx(params, p.id, state: %{"__agent_tokens__" => 200_000})
    assert {:error, msg} = AgentStep.execute(ctx)
    assert msg == "agent: execution token budget exhausted (200000/200000 tokens)"

    refute_receive {:anthropic_create_message, _, _}
  end

  test "refusal fails the step but the billed usage is still recorded", %{
    project: p,
    credential: c
  } do
    Application.put_env(
      :cartograph_backend,
      :anthropic_fake_response,
      {:ok,
       %{
         "stop_reason" => "refusal",
         "content" => [],
         "usage" => %{"input_tokens" => 40, "output_tokens" => 0}
       }}
    )

    ctx = ctx(%{"secret" => c.code, "prompt" => "Hi"}, p.id)
    assert {:error, "agent: the model declined this request (refusal)"} = AgentStep.execute(ctx)

    meta = metadata(ctx)["agent"]
    assert meta["inputTokens"] == 40
    assert meta["stopReason"] == "refusal"
  end

  test "max_tokens truncation fails the step, records usage, writes nothing to state", %{
    project: p,
    credential: c
  } do
    Application.put_env(
      :cartograph_backend,
      :anthropic_fake_response,
      {:ok,
       %{
         "stop_reason" => "max_tokens",
         "content" => [%{"type" => "text", "text" => "truncated..."}],
         "usage" => %{"input_tokens" => 10, "output_tokens" => 4096}
       }}
    )

    ctx = ctx(%{"secret" => c.code, "prompt" => "Hi"}, p.id)
    assert {:error, msg} = AgentStep.execute(ctx)

    assert msg ==
             "agent: response truncated at maxTokens=4096; raise maxTokens or shorten the prompt"

    meta = metadata(ctx)["agent"]
    assert meta["outputTokens"] == 4096
    assert meta["stopReason"] == "max_tokens"
  end

  test "an unexpected stop_reason fails the step", %{project: p, credential: c} do
    Application.put_env(
      :cartograph_backend,
      :anthropic_fake_response,
      {:ok, %{"stop_reason" => "pause_turn", "content" => []}}
    )

    ctx = ctx(%{"secret" => c.code, "prompt" => "Hi"}, p.id)
    assert {:error, "agent: unexpected stop_reason 'pause_turn'"} = AgentStep.execute(ctx)
  end

  test "an API error surfaces as a step error", %{project: p, credential: c} do
    Application.put_env(
      :cartograph_backend,
      :anthropic_fake_response,
      {:error, "HTTP 401: invalid x-api-key"}
    )

    ctx = ctx(%{"secret" => c.code, "prompt" => "Hi"}, p.id)
    assert {:error, msg} = AgentStep.execute(ctx)
    assert msg == "agent: Anthropic API error: HTTP 401: invalid x-api-key"
  end

  test "two agents cooperate through the shared state (writer -> editor)", %{
    project: p,
    credential: c
  } do
    # Writer: puts its answer under state["draft"] (as a `use`-chained job would).
    writer = ctx(%{"secret" => c.code, "prompt" => "Write a draft", "output" => "draft"}, p.id)
    assert {:ok, after_writer} = AgentStep.execute(writer)
    assert_receive {:anthropic_create_message, _, _}

    # Editor: reads {{draft}} from the same shared state and refines it.
    editor_params = %{"secret" => c.code, "prompt" => "Refine: {{draft}}", "output" => "review"}
    editor = %{ctx(editor_params, p.id) | state: after_writer.state}
    assert {:ok, after_editor} = AgentStep.execute(editor)

    assert_receive {:anthropic_create_message, _, body}
    assert body["messages"] == [%{"role" => "user", "content" => "Refine: Fake agent answer."}]
    assert StepContext.get_state(after_editor, "review") == "Fake agent answer."

    # Both calls count against the same execution budget (2 x (12 + 34)).
    assert StepContext.get_state(after_editor, "__agent_tokens__") == 92
  end
end
