defmodule CartographBackend.FilesTest do
  # NOT async: overrides the global :step_data_root sandbox for each test.
  use ExUnit.Case, async: false

  alias CartographBackend.Files
  alias CartographBackend.Steps.SafePath

  @moduletag :tmp_dir

  # Every function is scoped to a project; its sandbox is <root>/projects/<id>.
  @project_id 42

  setup %{tmp_dir: tmp} do
    previous = Application.get_env(:cartograph_backend, :step_data_root)
    Application.put_env(:cartograph_backend, :step_data_root, tmp)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cartograph_backend, :step_data_root, previous),
        else: Application.delete_env(:cartograph_backend, :step_data_root)
    end)

    root = SafePath.sandbox_root(@project_id)
    File.mkdir_p!(Path.join(root, "inbox"))
    File.write!(Path.join(root, "inbox/data.csv"), "a,b\n1,2\n")
    File.write!(Path.join(root, "readme.txt"), "hello")
    %{root: root}
  end

  defp upload(content, filename) do
    tmp = Path.join(System.tmp_dir!(), "up-#{System.unique_integer([:positive])}")
    File.write!(tmp, content)
    %Plug.Upload{path: tmp, filename: filename, content_type: "application/octet-stream"}
  end

  # ── list ──────────────────────────────────────────────────────────────────────

  test "list/2 of the project root shows dirs first, then files, with metadata" do
    assert {:ok, [dir, file]} = Files.list(@project_id, "")
    assert %{name: "inbox", isDir: true, size: nil} = dir
    assert %{name: "readme.txt", isDir: false, size: 5, modifiedAt: %DateTime{}} = file
  end

  test "list/2 of a subdirectory" do
    assert {:ok, [%{name: "data.csv", isDir: false}]} = Files.list(@project_id, "inbox")
  end

  test "list/2 of a missing directory → :not_found" do
    assert {:error, :not_found} = Files.list(@project_id, "ghost")
  end

  # ── SECURITY: confinement ─────────────────────────────────────────────────────

  test "paths escaping the project sandbox are rejected everywhere" do
    for evil <- ["..", "../..", "inbox/../..", "../#{@project_id + 1}"] do
      assert {:error, msg} = Files.list(@project_id, evil), "list(#{evil}) escaped"
      assert msg =~ "escapes the project sandbox"
    end

    # Absolute paths are anchored INSIDE the sandbox by the join (they cannot
    # escape); they just don't exist there.
    assert {:error, :not_found} = Files.list(@project_id, "/etc")

    assert {:error, _} = Files.delete(@project_id, "../outside.txt")
    assert {:error, _} = Files.resolve_download(@project_id, "../../etc/passwd")
    assert {:error, _} = Files.save_upload(@project_id, upload("x", "x.txt"), "../evil")
  end

  test "upload file name is reduced to its basename (no path smuggling)" do
    assert {:ok, "inbox/passwd"} =
             Files.save_upload(@project_id, upload("x", "../../../etc/passwd"), "inbox")

    assert File.exists?(Path.join(SafePath.sandbox_root(@project_id), "inbox/passwd"))
  end

  # ── upload / download / delete ────────────────────────────────────────────────

  test "save_upload/3 stores in the target dir and download resolves it" do
    assert {:ok, "inbox/new.txt"} =
             Files.save_upload(@project_id, upload("conteudo", "new.txt"), "inbox")

    assert {:ok, full, "new.txt"} = Files.resolve_download(@project_id, "inbox/new.txt")
    assert File.read!(full) == "conteudo"
  end

  test "save_upload/3 into a missing dir → :not_found" do
    assert {:error, :not_found} = Files.save_upload(@project_id, upload("x", "a.txt"), "nope")
  end

  test "resolve_download/2 refuses directories and missing files" do
    assert {:error, "Cannot download a directory"} = Files.resolve_download(@project_id, "inbox")
    assert {:error, :not_found} = Files.resolve_download(@project_id, "inbox/ghost.txt")
  end

  test "delete/2 removes files, refuses non-empty dirs, allows empty dirs", %{root: root} do
    assert :ok = Files.delete(@project_id, "inbox/data.csv")
    refute File.exists?(Path.join(root, "inbox/data.csv"))

    File.write!(Path.join(root, "inbox/keep.txt"), "k")
    assert {:error, "Directory is not empty"} = Files.delete(@project_id, "inbox")

    assert :ok = Files.delete(@project_id, "inbox/keep.txt")
    assert :ok = Files.delete(@project_id, "inbox")
    assert {:error, :not_found} = Files.delete(@project_id, "inbox/ghost.txt")
  end

  test "the project root itself cannot be deleted" do
    assert {:error, "Cannot delete the project root"} = Files.delete(@project_id, "")
  end

  # ── mkdir ─────────────────────────────────────────────────────────────────────

  test "mkdir/3 creates a new folder and reports its relative path", %{root: root} do
    assert {:ok, "inbox/nova"} = Files.mkdir(@project_id, "inbox", "nova")
    assert File.dir?(Path.join(root, "inbox/nova"))
    assert {:ok, [%{name: "nova", isDir: true} | _]} = Files.list(@project_id, "inbox")
  end

  test "mkdir/3 rejects invalid names and separators" do
    for bad <- ["", ".", "..", "a/b", "a\\b", "../evil"] do
      assert {:error, "Invalid folder name"} = Files.mkdir(@project_id, "", bad),
             "mkdir(#{inspect(bad)}) accepted"
    end
  end

  test "mkdir/3 refuses existing entries, missing parents and escapes" do
    assert {:error, "An entry with this name already exists"} =
             Files.mkdir(@project_id, "", "inbox")

    assert {:error, "An entry with this name already exists"} =
             Files.mkdir(@project_id, "", "readme.txt")

    assert {:error, :not_found} = Files.mkdir(@project_id, "ghost", "x")
    assert {:error, msg} = Files.mkdir(@project_id, "..", "x")
    assert msg =~ "escapes the project sandbox"
  end

  # ── ensure_root ───────────────────────────────────────────────────────────────

  test "ensure_root/1 creates the project sandbox when missing" do
    fresh = @project_id + 1
    refute File.dir?(SafePath.sandbox_root(fresh))
    assert :ok = Files.ensure_root(fresh)
    assert File.dir?(SafePath.sandbox_root(fresh))
  end
end
