defmodule CartographBackend.Steps.AgentDataGuardTest do
  @moduledoc """
  The §10 finding of `docs/design/ai-agent-tool-use.md`: a tool-enabled agent
  cannot *call* a step that writes files or runs SQL, but `parseJson` takes a
  model-chosen `result_key`, so it can write the state key such a step later
  reads. These are the sinks refusing that data without an explicit opt-in.
  """
  # NOT async: overrides the global :step_data_root sandbox for each test.
  # DataCase because the executeDatabase cases that get *past* the guard go on
  # to look the data source up in the database.
  use CartographBackend.DataCase, async: false

  alias CartographBackend.Engine.{Provenance, StepContext}

  alias CartographBackend.Steps.{
    ExecuteDatabaseStep,
    WriteJsonStep,
    WriteOutputStep,
    WriteXmlStep
  }

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous = Application.get_env(:cartograph_backend, :step_data_root)
    Application.put_env(:cartograph_backend, :step_data_root, tmp)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cartograph_backend, :step_data_root, previous),
        else: Application.delete_env(:cartograph_backend, :step_data_root)
    end)

    {:ok, tmp: tmp, out: Path.join(tmp, "out")}
  end

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

  # State as it looks after an agent's tool call wrote `key`.
  defp tainted(key, value), do: Provenance.mark_agent_written(%{key => value}, [key])

  describe "writeJson" do
    test "refuses an agent-written data_key and writes nothing", %{out: out} do
      path = Path.join(out, "rows.json")
      state = tainted("rows", [%{"id" => 1}])

      assert {:error, message} =
               WriteJsonStep.execute(ctx(%{"path" => path, "data_key" => "rows"}, state))

      assert message =~ "writeJson: state key 'rows' was written by an agent tool call"
      refute File.exists?(path)
    end

    test "writes it once the author opts in", %{out: out} do
      path = Path.join(out, "rows.json")
      state = tainted("rows", [%{"id" => 1}])
      params = %{"path" => path, "data_key" => "rows", "allowAgentData" => true}

      assert {:ok, _} = WriteJsonStep.execute(ctx(params, state))
      assert File.read!(path) == ~s([{"id":1}])
    end

    test "an author-written key is unaffected", %{out: out} do
      path = Path.join(out, "rows.json")

      assert {:ok, _} =
               WriteJsonStep.execute(
                 ctx(%{"path" => path, "data_key" => "rows"}, %{"rows" => [%{"id" => 1}]})
               )

      assert File.exists?(path)
    end
  end

  describe "writeXml" do
    test "refuses an agent-written data_key and writes nothing", %{out: out} do
      path = Path.join(out, "rows.xml")
      state = tainted("rows", [%{"id" => 1}])

      assert {:error, message} =
               WriteXmlStep.execute(ctx(%{"path" => path, "data_key" => "rows"}, state))

      assert message =~ "writeXml: state key 'rows' was written by an agent tool call"
      refute File.exists?(path)
    end

    test "writes it once the author opts in", %{out: out} do
      path = Path.join(out, "rows.xml")
      state = tainted("rows", [%{"id" => 1}])
      params = %{"path" => path, "data_key" => "rows", "allowAgentData" => true}

      assert {:ok, _} = WriteXmlStep.execute(ctx(params, state))
      assert File.read!(path) =~ "<id>1</id>"
    end
  end

  describe "writeOutput" do
    test "refuses agent-written transformed content", %{out: out} do
      state = tainted("transformed", %{"a.txt" => "OWNED"})

      assert {:error, message} = WriteOutputStep.execute(ctx(%{"path" => out}, state))
      assert message =~ "writeOutput: state key 'transformed' was written by an agent tool call"
      refute File.exists?(Path.join(out, "processed_a.txt"))
    end

    test "refuses an agent-written file list on the copy path", %{tmp: tmp, out: out} do
      # Without `transformed`, writeOutput copies state["files"] — so that is
      # the key the guard has to look at instead.
      File.write!(Path.join(tmp, "a.txt"), "conteudo")
      state = tainted("files", [Path.join(tmp, "a.txt")])

      assert {:error, message} = WriteOutputStep.execute(ctx(%{"path" => out}, state))
      assert message =~ "state key 'files'"
      refute File.exists?(Path.join(out, "a.txt"))
    end

    test "writes it once the author opts in", %{out: out} do
      state = tainted("transformed", %{"a.txt" => "CONTEUDO"})
      params = %{"path" => out, "allowAgentData" => true}

      assert {:ok, _} = WriteOutputStep.execute(ctx(params, state))
      assert File.read!(Path.join(out, "processed_a.txt")) == "CONTEUDO"
    end
  end

  describe "executeDatabase" do
    @params %{"source" => "pg-main", "query" => "INSERT INTO t VALUES ($1)"}

    test "refuses agent-written rows before it even resolves the data source" do
      state = tainted("rows", [%{"id" => 1}])
      params = Map.put(@params, "rows_from", "rows")

      assert {:error, message} = ExecuteDatabaseStep.execute(ctx(params, state))
      assert message =~ "executeDatabase: state key 'rows' was written by an agent tool call"
    end

    test "the opt-in gets past the guard" do
      # The data source does not exist here, so reaching *that* error is the
      # proof the provenance guard let it through.
      state = tainted("rows", [%{"id" => 1}])
      params = @params |> Map.put("rows_from", "rows") |> Map.put("allowAgentData", true)

      assert {:error, message} = ExecuteDatabaseStep.execute(ctx(params, state))
      assert message =~ "data source 'pg-main' not found"
    end

    test "without rows_from there is no state key to guard" do
      state = tainted("rows", [%{"id" => 1}])

      assert {:error, message} = ExecuteDatabaseStep.execute(ctx(@params, state))
      assert message =~ "data source 'pg-main' not found"
    end
  end
end
