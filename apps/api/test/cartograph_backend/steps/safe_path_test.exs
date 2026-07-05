defmodule CartographBackend.Steps.SafePathTest do
  # NOT async: overrides the global :step_data_root sandbox for each test.
  use ExUnit.Case, async: false

  alias CartographBackend.Steps.SafePath

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous = Application.get_env(:cartograph_backend, :step_data_root)
    Application.put_env(:cartograph_backend, :step_data_root, tmp)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cartograph_backend, :step_data_root, previous),
        else: Application.delete_env(:cartograph_backend, :step_data_root)
    end)

    %{tmp: tmp}
  end

  test "global scope keeps historical behavior", %{tmp: tmp} do
    assert {:ok, path} = SafePath.resolve(Path.join(tmp, "inbox/a.csv"))
    assert path == Path.join(tmp, "inbox/a.csv")
    assert {:error, _} = SafePath.resolve("/etc/passwd")
  end

  test "project scope confines to projects/<id> and strips the data/ prefix", %{tmp: tmp} do
    base = Path.join(tmp, "projects/7")

    # the same DSL path works globally and inside a project
    assert {:ok, Path.join(base, "inbox")} == SafePath.resolve("data/inbox", 7)
    assert {:ok, Path.join(base, "inbox")} == SafePath.resolve("inbox", 7)
    assert {:ok, base} == SafePath.resolve("", 7)
    assert {:ok, base} == SafePath.resolve("data", 7)
  end

  test "project scope blocks escapes to the global root and other projects" do
    for evil <- ["..", "../..", "../8", "inbox/../../8", "../inbox"] do
      assert {:error, msg} = SafePath.resolve(evil, 7), "resolve(#{evil}, 7) escaped"
      assert msg =~ "outside the allowed data directory"
    end
  end

  test "absolute paths pass only when already inside the project sandbox", %{tmp: tmp} do
    inside = Path.join(tmp, "projects/7/inbox/x.csv")
    assert {:ok, ^inside} = SafePath.resolve(inside, 7)

    # global sandbox path is NOT visible from a project scope
    assert {:error, _} = SafePath.resolve(Path.join(tmp, "inbox/x.csv"), 7)
    # neither is another project's
    assert {:error, _} = SafePath.resolve(Path.join(tmp, "projects/8/x.csv"), 7)
    assert {:error, _} = SafePath.resolve("/etc/passwd", 7)
  end

  test "sandbox_root/1", %{tmp: tmp} do
    assert SafePath.sandbox_root(nil) == tmp
    assert SafePath.sandbox_root(3) == Path.join(tmp, "projects/3")
  end
end
