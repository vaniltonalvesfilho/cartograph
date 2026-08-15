defmodule CartographBackend.Engine.ProvenanceTest do
  use ExUnit.Case, async: true

  alias CartographBackend.Engine.{Provenance, StepContext}

  @key "__agent_written__"

  defp ctx(params, state) do
    %StepContext{
      params: params,
      state: state,
      execution_id: 1,
      step_execution_id: 1,
      project_id: nil,
      log: fn _level, _msg -> :ok end,
      cancelled?: fn -> false end
    }
  end

  describe "reserved?/1" do
    test "the whole __ prefix is engine bookkeeping, not one hardcoded key" do
      assert Provenance.reserved?("__agent_tokens__")
      assert Provenance.reserved?(@key)
      assert Provenance.reserved?("__anything_we_add_later")
      refute Provenance.reserved?("files")
      refute Provenance.reserved?("_files")
      refute Provenance.reserved?(:files)
    end
  end

  describe "guard_reserved/2" do
    test "restores reserved keys a tool overwrote and drops ones it invented" do
      before_state = %{"__agent_tokens__" => 199_000, "files" => ["a.json"]}

      after_state = %{
        "__agent_tokens__" => 0,
        @key => ["totally", "safe"],
        "files" => ["b.json"],
        "rows" => [%{"id" => 1}]
      }

      assert Provenance.guard_reserved(before_state, after_state) == %{
               "__agent_tokens__" => 199_000,
               "files" => ["b.json"],
               "rows" => [%{"id" => 1}]
             }
    end

    test "a reserved key the tool deleted comes back" do
      assert Provenance.guard_reserved(%{"__agent_tokens__" => 42}, %{"files" => []}) ==
               %{"__agent_tokens__" => 42, "files" => []}
    end
  end

  describe "mark_agent_written/2 and clear_agent_written/2" do
    test "marks accumulate, dedupe and sort" do
      state =
        %{}
        |> Provenance.mark_agent_written(["files"])
        |> Provenance.mark_agent_written(["rows", "files"])

      assert Provenance.agent_written(state) == ["files", "rows"]
      assert Provenance.agent_written?(state, "files")
      refute Provenance.agent_written?(state, "other")
    end

    test "marking nothing does not create the record" do
      assert Provenance.mark_agent_written(%{"x" => 1}, []) == %{"x" => 1}
    end

    test "a reserved key is never marked — it is not data" do
      assert Provenance.mark_agent_written(%{}, ["__agent_tokens__", @key]) == %{}
    end

    test "clearing the last mark removes the record entirely" do
      state = Provenance.mark_agent_written(%{}, ["files", "rows"])

      assert Provenance.clear_agent_written(state, ["files"]) == %{@key => ["rows"]}
      assert Provenance.clear_agent_written(state, ["files", "rows"]) == %{}
    end

    test "a corrupt record reads as no marks rather than crashing" do
      # The record lives in the shared state, which a `use`-chained job written
      # before this feature — or a hand-edited row — can carry anything in.
      refute Provenance.agent_written?(%{@key => "files"}, "files")
      assert Provenance.agent_written(%{@key => ["files", 7]}) == ["files"]
    end
  end

  describe "reconcile/2" do
    test "an ordinary step rewriting a marked key clears the mark" do
      before_state = %{"files" => ["agent/choice.json"], @key => ["files"]}
      after_state = %{"files" => ["author/choice.json"], @key => ["files"]}

      assert Provenance.reconcile(before_state, after_state) == %{
               "files" => ["author/choice.json"]
             }
    end

    test "marks a step added itself survive its own reconcile" do
      # This is what lets AgentStep record its tool writes without the
      # interpreter undoing them on the way out.
      before_state = %{"files" => ["a.json"]}
      after_state = %{"files" => ["b.json"], @key => ["files"]}

      assert Provenance.reconcile(before_state, after_state) == after_state
    end

    test "a marked key the step did not touch stays marked" do
      before_state = %{"rows" => [1], @key => ["rows"]}
      after_state = %{"rows" => [1], "report" => "text", @key => ["rows"]}

      assert Provenance.reconcile(before_state, after_state) == after_state
    end

    test "clearing only some marks keeps the rest" do
      before_state = %{"files" => [1], "rows" => [2], @key => ["files", "rows"]}
      after_state = %{"files" => [9], "rows" => [2], @key => ["files", "rows"]}

      assert Provenance.reconcile(before_state, after_state) == %{
               "files" => [9],
               "rows" => [2],
               @key => ["rows"]
             }
    end
  end

  describe "guard_consumption/3" do
    test "refuses an agent-written key and names the opt-in" do
      state = Provenance.mark_agent_written(%{"rows" => [%{"id" => 1}]}, ["rows"])

      assert {:error, message} =
               Provenance.guard_consumption(ctx(%{}, state), "rows", "executeDatabase")

      assert message =~ "executeDatabase: state key 'rows' was written by an agent tool call"
      assert message =~ "allowAgentData true"
    end

    test "the author opt-in lets it through, as a boolean or as canvas text" do
      state = Provenance.mark_agent_written(%{"rows" => []}, ["rows"])

      assert :ok =
               Provenance.guard_consumption(
                 ctx(%{"allowAgentData" => true}, state),
                 "rows",
                 "writeJson"
               )

      assert :ok =
               Provenance.guard_consumption(
                 ctx(%{"allowAgentData" => "true"}, state),
                 "rows",
                 "writeJson"
               )
    end

    test "anything other than true is not an opt-in" do
      state = Provenance.mark_agent_written(%{"rows" => []}, ["rows"])

      for value <- [false, "false", "yes", 1, nil] do
        assert {:error, _} =
                 Provenance.guard_consumption(
                   ctx(%{"allowAgentData" => value}, state),
                   "rows",
                   "writeJson"
                 )
      end
    end

    test "unmarked keys, absent params and empty lists pass" do
      state = Provenance.mark_agent_written(%{"rows" => [], "safe" => []}, ["rows"])
      c = ctx(%{}, state)

      assert :ok = Provenance.guard_consumption(c, "safe", "writeJson")
      # `rows_from` is optional on executeDatabase; nil must not be treated as a key.
      assert :ok = Provenance.guard_consumption(c, nil, "executeDatabase")
      assert :ok = Provenance.guard_consumption(c, [], "writeXml")
    end

    test "one tainted key in a list is enough to refuse" do
      state = Provenance.mark_agent_written(%{"a" => [], "b" => []}, ["b"])

      assert {:error, message} =
               Provenance.guard_consumption(ctx(%{}, state), ["a", "b"], "writeOutput")

      assert message =~ "'b'"
    end
  end
end
