defmodule CartographBackend.Steps.WriteOutputStepTest do
  # NOT async: overrides the global :step_data_root sandbox for each test.
  use ExUnit.Case, async: false

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Steps.WriteOutputStep

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous = Application.get_env(:cartograph_backend, :step_data_root)
    Application.put_env(:cartograph_backend, :step_data_root, tmp)
    on_exit(fn ->
      if previous,
        do: Application.put_env(:cartograph_backend, :step_data_root, previous),
        else: Application.delete_env(:cartograph_backend, :step_data_root)
    end)

    inbox = Path.join(tmp, "inbox")
    File.mkdir_p!(inbox)
    File.write!(Path.join(inbox, "a.txt"), "conteudo A")
    File.write!(Path.join(inbox, "b.txt"), "conteudo B")

    {:ok, tmp: tmp, inbox: inbox, outbox: Path.join(tmp, "outbox")}
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

  # ── Transformed content (pipeline with a transform step) ─────────────────────

  test "writes transformed content as processed_* files", %{outbox: outbox} do
    state = %{"transformed" => %{"a.txt" => "CONTEUDO A"}}
    assert {:ok, _} = WriteOutputStep.execute(ctx(%{"path" => outbox}, state))
    assert File.read!(Path.join(outbox, "processed_a.txt")) == "CONTEUDO A"
  end

  test "an empty transformed map writes nothing and does not fall back to copying",
       %{inbox: inbox, outbox: outbox} do
    state = %{"transformed" => %{}, "files" => [Path.join(inbox, "a.txt")]}
    assert {:ok, _} = WriteOutputStep.execute(ctx(%{"path" => outbox}, state))
    assert {:ok, []} = File.ls(outbox)
  end

  # ── File transfer fallback (pipeline without a transform step) ───────────────

  test "without transformed state, copies the files list to the output dir",
       %{inbox: inbox, outbox: outbox} do
    files = [Path.join(inbox, "a.txt"), Path.join(inbox, "b.txt")]
    assert {:ok, _} = WriteOutputStep.execute(ctx(%{"path" => outbox}, %{"files" => files}))

    assert File.read!(Path.join(outbox, "a.txt")) == "conteudo A"
    assert File.read!(Path.join(outbox, "b.txt")) == "conteudo B"
  end

  test "copy fallback fails naming the file when a source is missing",
       %{inbox: inbox, outbox: outbox} do
    files = [Path.join(inbox, "missing.txt")]
    assert {:error, msg} = WriteOutputStep.execute(ctx(%{"path" => outbox}, %{"files" => files}))
    assert msg =~ "Failed to copy missing.txt"
  end

  test "copy fallback refuses source files outside the sandbox", %{outbox: outbox} do
    assert {:error, msg} =
             WriteOutputStep.execute(ctx(%{"path" => outbox}, %{"files" => ["/etc/passwd"]}))

    assert msg =~ "Failed to copy passwd"
  end

  test "with neither transformed nor files, writes nothing and succeeds", %{outbox: outbox} do
    assert {:ok, _} = WriteOutputStep.execute(ctx(%{"path" => outbox}, %{}))
    assert {:ok, []} = File.ls(outbox)
  end

  # ── Path confinement ──────────────────────────────────────────────────────────

  test "output path outside the sandbox is rejected" do
    assert {:error, msg} = WriteOutputStep.execute(ctx(%{"path" => "/etc"}, %{}))
    assert msg =~ "outside the allowed data directory"
  end
end
