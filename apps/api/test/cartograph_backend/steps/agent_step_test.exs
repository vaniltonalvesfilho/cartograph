defmodule CartographBackend.Steps.AgentStepTest do
  # NOT async: registers the test pid / fake response via the app env.
  use CartographBackend.DataCase, async: false

  alias CartographBackend.{Agents, Executions}
  alias CartographBackend.Engine.{Provenance, StepContext}
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

  # ── Phase 2: tool use ────────────────────────────────────────────────────────

  describe "tool use" do
    @files ["/data/a.json", "/data/b.txt"]

    defp tool_block(id, name, input),
      do: %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}

    defp tool_use_response(blocks, text \\ nil) do
      content = if text, do: [%{"type" => "text", "text" => text} | blocks], else: blocks

      {:ok,
       %{
         "model" => "claude-opus-4-8",
         "stop_reason" => "tool_use",
         "content" => content,
         "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
       }}
    end

    defp end_turn_response(text) do
      {:ok,
       %{
         "model" => "claude-opus-4-8",
         "stop_reason" => "end_turn",
         "content" => [%{"type" => "text", "text" => text}],
         "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
       }}
    end

    defp script(responses),
      do: Application.put_env(:cartograph_backend, :anthropic_fake_responses, responses)

    defp children(ctx) do
      StepExecution
      |> Repo.all()
      |> Enum.filter(&(&1.parent_step_execution_id == ctx.step_execution_id))
      |> Enum.sort_by(& &1.step_order)
    end

    setup do
      on_exit(fn ->
        Application.delete_env(:cartograph_backend, :anthropic_fake_responses)
      end)
    end

    test "a tool call runs the real step, threads state, and is persisted as a child", %{
      project: p,
      credential: c
    } do
      script([
        tool_use_response([tool_block("tu_1", "filter", %{"extension" => "json"})], "Filtering."),
        end_turn_response("Only a.json is JSON.")
      ])

      ctx =
        ctx(
          %{"secret" => c.code, "prompt" => "Which files are JSON?", "tools" => "filter"},
          p.id,
          state: %{"files" => @files}
        )

      assert {:ok, out} = AgentStep.execute(ctx)

      # The real step ran against the shared state, and the result threaded out.
      assert StepContext.get_state(out, "files") == ["/data/a.json"]
      assert StepContext.get_state(out, "agent_result") == "Only a.json is JSON."

      # Both turns billed against the same budget.
      assert StepContext.get_state(out, "__agent_tokens__") == 30

      assert [child] = children(ctx)
      assert child.step_name == "filter"
      assert child.step_order == 1
      assert child.status == "SUCCESS"
      assert child.execution_id == @execution_id
      # A tool call has no node in the authored DSL.
      assert child.flow_node_id == nil
    end

    test "the first request carries the tool definitions; the second carries the result", %{
      project: p,
      credential: c
    } do
      script([
        tool_use_response([tool_block("tu_1", "filter", %{"extension" => "json"})]),
        end_turn_response("done")
      ])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter"}, p.id,
          state: %{"files" => @files}
        )

      assert {:ok, _} = AgentStep.execute(ctx)

      assert_receive {:anthropic_create_message, _, first}

      assert [%{"name" => "filter", "description" => desc, "input_schema" => schema}] =
               first["tools"]

      assert is_binary(desc)
      assert schema["type"] == "object"

      assert_receive {:anthropic_create_message, _, second}
      # Tool definitions stay identical across turns (a stable cacheable prefix).
      assert second["tools"] == first["tools"]

      assert [
               %{"role" => "user", "content" => "go"},
               %{"role" => "assistant", "content" => _},
               %{"role" => "user", "content" => results}
             ] = second["messages"]

      assert [%{"type" => "tool_result", "tool_use_id" => "tu_1", "content" => content}] = results
      # The result is the state delta, not the whole state.
      assert Jason.decode!(content) == %{"files" => ["/data/a.json"]}
    end

    test "parallel tool blocks all run, in order, and return in ONE user message", %{
      project: p,
      credential: c
    } do
      script([
        tool_use_response([
          tool_block("tu_1", "filter", %{"extension" => "json"}),
          tool_block("tu_2", "validate", %{"email" => "nope@@example"})
        ]),
        end_turn_response("done")
      ])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter,validate"}, p.id,
          state: %{"files" => @files}
        )

      assert {:ok, _} = AgentStep.execute(ctx)
      assert_receive {:anthropic_create_message, _, _first}
      assert_receive {:anthropic_create_message, _, second}

      [_user, _assistant, %{"content" => results}] = second["messages"]

      # Both results in a single user message — splitting them would train the
      # model out of requesting tools in parallel.
      assert [%{"tool_use_id" => "tu_1"}, %{"tool_use_id" => "tu_2"}] = results

      assert [first_child, second_child] = children(ctx)
      assert {first_child.step_name, first_child.step_order} == {"filter", 1}
      assert {second_child.step_name, second_child.step_order} == {"validate", 2}
    end

    test "a failing tool returns is_error, keeps the loop alive, and discards its state", %{
      project: p,
      credential: c
    } do
      script([
        # parseXml without the required root_element fails the step.
        tool_use_response([tool_block("tu_1", "parseXml", %{"path" => "data/x.xml"})]),
        end_turn_response("I could not parse it.")
      ])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "parseXml"}, p.id,
          state: %{"files" => @files}
        )

      # The job does NOT fail — the model gets the error and adapts.
      assert {:ok, out} = AgentStep.execute(ctx)
      assert StepContext.get_state(out, "agent_result") == "I could not parse it."
      assert StepContext.get_state(out, "files") == @files

      assert_receive {:anthropic_create_message, _, _first}
      assert_receive {:anthropic_create_message, _, second}
      [_user, _assistant, %{"content" => [result]}] = second["messages"]
      assert result["is_error"] == true
      assert result["content"] =~ "root_element"

      assert [child] = children(ctx)
      assert child.status == "FAILED"
      assert child.error_message =~ "root_element"
    end

    test "a hallucinated tool name is refused without crashing or creating a child", %{
      project: p,
      credential: c
    } do
      script([
        tool_use_response([
          tool_block("tu_1", "executeDatabase", %{"sql" => "DROP TABLE users"})
        ]),
        end_turn_response("ok")
      ])

      ctx = ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter"}, p.id)

      assert {:ok, _} = AgentStep.execute(ctx)
      assert_receive {:anthropic_create_message, _, _first}
      assert_receive {:anthropic_create_message, _, second}

      [_user, _assistant, %{"content" => [result]}] = second["messages"]
      assert result["is_error"] == true
      assert result["content"] =~ "not available"

      # Nothing was executed and nothing was recorded.
      assert children(ctx) == []
    end

    test "a step that is not agent-callable fails before any API call", %{
      project: p,
      credential: c
    } do
      ctx = ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "notify"}, p.id)

      assert {:error, msg} = AgentStep.execute(ctx)
      assert msg =~ "not available to agents: notify"
      refute_receive {:anthropic_create_message, _, _}
    end

    test "an unknown step name in tools fails before any API call", %{project: p, credential: c} do
      ctx = ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter,flter"}, p.id)

      assert {:error, msg} = AgentStep.execute(ctx)
      assert msg =~ "flter"
      refute_receive {:anthropic_create_message, _, _}
    end

    test "without a tools param the request carries no tool definitions", %{
      project: p,
      credential: c
    } do
      assert {:ok, _} = AgentStep.execute(ctx(%{"secret" => c.code, "prompt" => "go"}, p.id))

      assert_receive {:anthropic_create_message, _, body}
      refute Map.has_key?(body, "tools")
    end

    test "maxIterations is validated to 1..10", %{project: p, credential: c} do
      ctx = ctx(%{"secret" => c.code, "prompt" => "go", "maxIterations" => 11}, p.id)

      assert {:error, msg} = AgentStep.execute(ctx)
      assert msg == "agent: 'maxIterations' must be an integer between 1 and 10"
      refute_receive {:anthropic_create_message, _, _}
    end

    test "exhausting maxIterations fails the step and writes nothing to state", %{
      project: p,
      credential: c
    } do
      # The model never stops asking for tools.
      script(List.duplicate(tool_use_response([tool_block("tu", "filter", %{})]), 3))

      ctx =
        ctx(
          %{"secret" => c.code, "prompt" => "go", "tools" => "filter", "maxIterations" => 2},
          p.id,
          state: %{"files" => @files}
        )

      assert {:error, msg} = AgentStep.execute(ctx)
      assert msg =~ "reached maxIterations=2"

      # Exactly two API calls, then a stop — a half-finished agent must not
      # hand a partial answer downstream.
      assert_receive {:anthropic_create_message, _, _}
      assert_receive {:anthropic_create_message, _, _}
      refute_receive {:anthropic_create_message, _, _}
    end

    test "the token budget is shared across the whole loop", %{project: p, credential: c} do
      script([
        tool_use_response([tool_block("tu_1", "filter", %{"extension" => "json"})]),
        end_turn_response("unreachable")
      ])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter"}, p.id,
          state: %{"files" => @files},
          budget: 10
        )

      # First turn is allowed (0 < 10) and bills 15; the second is refused.
      assert {:error, msg} = AgentStep.execute(ctx)
      assert msg == "agent: execution token budget exhausted (15/10 tokens)"

      # The tool still ran, and the billed usage is still on record.
      assert [child] = children(ctx)
      assert child.status == "SUCCESS"
      assert metadata(ctx)["agent"]["outputTokens"] == 5
    end

    test "usage is billed per turn and the metadata carries the run's total", %{
      project: p,
      credential: c
    } do
      # Two API calls, 10 in / 5 out each. Recording only the last turn would
      # under-report what the step actually spent, and the execution's cost
      # display sums exactly one number per step.
      script([
        tool_use_response([tool_block("tu_1", "filter", %{"extension" => "json"})]),
        end_turn_response("Only a.json is JSON.")
      ])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter"}, p.id,
          state: %{"files" => @files}
        )

      assert {:ok, _} = AgentStep.execute(ctx)

      meta = metadata(ctx)["agent"]
      assert meta["inputTokens"] == 20
      assert meta["outputTokens"] == 10
      assert meta["turns"] == 2
      # opus 4-8: $5/$25 per MTok, over both turns.
      assert_in_delta meta["estimatedCostUsd"], 0.00035, 1.0e-9
      # The stop reason describes how the run ended, not how a turn ended.
      assert meta["stopReason"] == "end_turn"
    end

    test "a turn over the per-turn cap still answers every tool_use block", %{
      project: p,
      credential: c
    } do
      # Nine blocks against a cap of eight. The API rejects a turn whose
      # tool_results don't cover its tool_uses, so the ninth must come back as
      # a refusal rather than being dropped.
      blocks =
        for i <- 1..9, do: tool_block("tu_#{i}", "filter", %{"extension" => "json"})

      script([tool_use_response(blocks), end_turn_response("Fewer next time.")])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter"}, p.id,
          state: %{"files" => @files}
        )

      assert {:ok, _} = AgentStep.execute(ctx)

      assert_receive {:anthropic_create_message, _, _first}
      assert_receive {:anthropic_create_message, _, second}
      [_user, _assistant, %{"content" => results}] = second["messages"]

      assert length(results) == 9
      assert Enum.map(results, & &1["tool_use_id"]) == Enum.map(1..9, &"tu_#{&1}")

      refused = List.last(results)
      assert refused["is_error"] == true
      assert refused["content"] =~ "more than 8 tool calls"

      # Only the eight under the cap actually ran.
      assert length(children(ctx)) == 8
    end

    # ── Regressions from the security audit of 2026-08-01 ──────────────────────

    test "a tool cannot overwrite the reserved token counter", %{project: p, credential: c} do
      # parseJson takes a model-chosen result_key, so without a guard the model
      # could reset the only ceiling that bounds the whole execution.
      script([
        tool_use_response([
          tool_block("tu_1", "parseJson", %{
            "path" => "nope.json",
            "result_key" => "__agent_tokens__"
          })
        ]),
        end_turn_response("done")
      ])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "parseJson"}, p.id,
          state: %{"__agent_tokens__" => 199_000}
        )

      assert {:ok, out} = AgentStep.execute(ctx)
      # 199_000 preserved, plus the two turns billed here (15 each).
      assert StepContext.get_state(out, "__agent_tokens__") == 199_030
    end

    # ── Provenance (§10 of the spec) ──────────────────────────────────────────

    test "every state key a tool call writes is recorded as agent-written", %{
      project: p,
      credential: c
    } do
      script([
        tool_use_response([tool_block("tu_1", "filter", %{"extension" => "json"})]),
        end_turn_response("Only a.json is JSON.")
      ])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter"}, p.id,
          state: %{"files" => @files}
        )

      assert {:ok, out} = AgentStep.execute(ctx)

      # `filter` rewrote state["files"], so a later writeOutput/executeDatabase
      # reading it now needs the author's explicit allowAgentData.
      assert Provenance.agent_written(out.state) == ["files"]
    end

    test "the agent's own answer is not marked — the author chose that key", %{
      project: p,
      credential: c
    } do
      # `output` is named in the DSL by the author, who thereby already decided
      # to put a model answer there. `result_key` on a tool is chosen by the
      # model, which is the asymmetry that makes §10 a finding at all.
      script([end_turn_response("APPROVED")])

      ctx = ctx(%{"secret" => c.code, "prompt" => "go", "output" => "review"}, p.id)

      assert {:ok, out} = AgentStep.execute(ctx)
      assert StepContext.get_state(out, "review") == "APPROVED"
      assert Provenance.agent_written(out.state) == []
    end

    test "a failed tool call marks nothing", %{project: p, credential: c} do
      script([
        tool_use_response([tool_block("tu_1", "parseXml", %{"path" => "missing.xml"})]),
        end_turn_response("I could not read it.")
      ])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "parseXml"}, p.id,
          state: %{"files" => @files}
        )

      assert {:ok, out} = AgentStep.execute(ctx)
      # Its ctx was discarded, so there is no agent-written value to record.
      assert Provenance.agent_written(out.state) == []
    end

    test "the reserved namespace is never shown to the model", %{project: p, credential: c} do
      script([
        tool_use_response([tool_block("tu_1", "filter", %{"extension" => "json"})]),
        end_turn_response("done")
      ])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter"}, p.id,
          state: %{"files" => @files}
        )

      assert {:ok, _out} = AgentStep.execute(ctx)

      assert_receive {:anthropic_create_message, _, _first}
      assert_receive {:anthropic_create_message, _, second}
      [_user, _assistant, %{"content" => [result]}] = second["messages"]

      # The delta is the model's view of what the tool did; engine bookkeeping
      # is not part of it, and telling the model about the record would only
      # invite it to reason about evading it.
      assert result["content"] == ~s({"files":["/data/a.json"]})
      refute result["content"] =~ "__agent"
    end

    test "a tool that raises on a model-written param does not fail the execution", %{
      project: p,
      credential: c
    } do
      # `filter` calls String.downcase/1 on the param; an integer raises rather
      # than returning {:error, _}. The step must survive it.
      script([
        tool_use_response([tool_block("tu_1", "filter", %{"extension" => 7})]),
        end_turn_response("I will try something else.")
      ])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter"}, p.id,
          state: %{"files" => @files}
        )

      assert {:ok, out} = AgentStep.execute(ctx)
      assert StepContext.get_state(out, "agent_result") == "I will try something else."

      assert_receive {:anthropic_create_message, _, _first}
      assert_receive {:anthropic_create_message, _, second}
      [_user, _assistant, %{"content" => [result]}] = second["messages"]
      assert result["is_error"] == true
      assert result["content"] =~ "raised"

      # The child row must not be left stuck in RUNNING.
      assert [child] = children(ctx)
      assert child.status == "FAILED"
    end

    test "tool calls in one turn are capped", %{project: p, credential: c} do
      blocks = for i <- 1..12, do: tool_block("tu_#{i}", "filter", %{"extension" => "json"})
      script([tool_use_response(blocks), end_turn_response("done")])

      ctx =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter"}, p.id,
          state: %{"files" => @files}
        )

      assert {:ok, _} = AgentStep.execute(ctx)
      # Eight executed; the rest refused without touching the database.
      assert length(children(ctx)) == 8
    end

    test "the regex validator is not offered to agents", %{project: p, credential: c} do
      # A model-written pattern would be compiled and run with no match timeout.
      assert {:ok, schema} = CartographBackend.Steps.Registry.tool_schema("validate")
      refute Map.has_key?(schema.input_schema["properties"], "regex")
      refute Map.has_key?(schema.input_schema["properties"], "pattern")

      script([
        tool_use_response([
          tool_block("tu_1", "validate", %{"regex" => "rows.sku", "pattern" => "(a+)+$"})
        ]),
        end_turn_response("done")
      ])

      ctx = ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "validate"}, p.id)
      # The step itself still rejects params it was not given a target for.
      assert {:ok, _} = AgentStep.execute(ctx)
    end

    test "a stop mid-turn skips the pending tool calls and makes no further API call", %{
      project: p,
      credential: c
    } do
      # Exactly one response is scripted, so a second API call would come back
      # as "scripted responses exhausted" — {:ok, _} is what proves we stopped.
      script([
        tool_use_response([
          tool_block("tu_1", "filter", %{"extension" => "json"}),
          tool_block("tu_2", "filter", %{"extension" => "txt"})
        ])
      ])

      base =
        ctx(%{"secret" => c.code, "prompt" => "go", "tools" => "filter"}, p.id,
          state: %{"files" => @files}
        )

      # Cancelled the moment the first API call has been made: the fake pops
      # the scripted list, so an empty list means the turn was taken. Driving
      # it off real progress keeps this from depending on how many times the
      # implementation happens to consult the flag.
      cancelled = %{
        base
        | cancelled?: fn ->
            Application.get_env(:cartograph_backend, :anthropic_fake_responses) == []
          end
      }

      assert {:ok, out} = AgentStep.execute(cancelled)

      # Neither queued tool ran, and the state is untouched.
      assert StepContext.get_state(out, "files") == @files
      assert children(base) == []

      assert_receive {:anthropic_create_message, _, _}
      refute_receive {:anthropic_create_message, _, _}
    end
  end
end
