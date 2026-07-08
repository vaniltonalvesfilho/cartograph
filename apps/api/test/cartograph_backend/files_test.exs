defmodule CartographBackend.FilesTest do
  # NOT async: overrides the global :step_data_root sandbox for each test.
  use ExUnit.Case, async: false

  alias CartographBackend.Files

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous = Application.get_env(:cartograph_backend, :step_data_root)
    Application.put_env(:cartograph_backend, :step_data_root, tmp)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cartograph_backend, :step_data_root, previous),
        else: Application.delete_env(:cartograph_backend, :step_data_root)
    end)

    File.mkdir_p!(Path.join(tmp, "inbox"))
    File.write!(Path.join(tmp, "inbox/data.csv"), "a,b\n1,2\n")
    File.write!(Path.join(tmp, "readme.txt"), "hello")
    :ok
  end

  defp upload(content, filename) do
    tmp = Path.join(System.tmp_dir!(), "up-#{System.unique_integer([:positive])}")
    File.write!(tmp, content)
    %Plug.Upload{path: tmp, filename: filename, content_type: "application/octet-stream"}
  end

  # ── list ──────────────────────────────────────────────────────────────────────

  test "list/1 of the root shows dirs first, then files, with metadata" do
    assert {:ok, [dir, file]} = Files.list("")
    assert %{name: "inbox", isDir: true, size: nil} = dir
    assert %{name: "readme.txt", isDir: false, size: 5, modifiedAt: %DateTime{}} = file
  end

  test "list/1 of a subdirectory" do
    assert {:ok, [%{name: "data.csv", isDir: false}]} = Files.list("inbox")
  end

  test "list/1 of a missing directory → :not_found" do
    assert {:error, :not_found} = Files.list("ghost")
  end

  # ── SECURITY: confinement ─────────────────────────────────────────────────────

  test "paths escaping the sandbox are rejected everywhere" do
    for evil <- ["..", "../..", "inbox/../.."] do
      assert {:error, msg} = Files.list(evil), "list(#{evil}) escaped"
      assert msg =~ "outside the allowed data directory"
    end

    # Absolute paths are anchored INSIDE the root by the join (they cannot
    # escape); they just don't exist there.
    assert {:error, :not_found} = Files.list("/etc")

    assert {:error, _} = Files.delete("../outside.txt")
    assert {:error, _} = Files.resolve_download("../../etc/passwd")
    assert {:error, _} = Files.save_upload(upload("x", "x.txt"), "../evil")
  end

  test "upload file name is reduced to its basename (no path smuggling)" do
    assert {:ok, "inbox/passwd"} = Files.save_upload(upload("x", "../../../etc/passwd"), "inbox")

    assert File.exists?(
             Path.join(Application.get_env(:cartograph_backend, :step_data_root), "inbox/passwd")
           )
  end

  # ── upload / download / delete ────────────────────────────────────────────────

  test "save_upload/2 stores in the target dir and download resolves it" do
    assert {:ok, "inbox/new.txt"} = Files.save_upload(upload("conteudo", "new.txt"), "inbox")
    assert {:ok, full, "new.txt"} = Files.resolve_download("inbox/new.txt")
    assert File.read!(full) == "conteudo"
  end

  test "save_upload/2 into a missing dir → :not_found" do
    assert {:error, :not_found} = Files.save_upload(upload("x", "a.txt"), "nope")
  end

  test "resolve_download/1 refuses directories and missing files" do
    assert {:error, "Cannot download a directory"} = Files.resolve_download("inbox")
    assert {:error, :not_found} = Files.resolve_download("inbox/ghost.txt")
  end

  test "delete/1 removes files, refuses non-empty dirs, allows empty dirs" do
    assert :ok = Files.delete("inbox/data.csv")

    refute File.exists?(
             Path.join(
               Application.get_env(:cartograph_backend, :step_data_root),
               "inbox/data.csv"
             )
           )

    File.write!(
      Path.join(Application.get_env(:cartograph_backend, :step_data_root), "inbox/keep.txt"),
      "k"
    )

    assert {:error, "Directory is not empty"} = Files.delete("inbox")

    assert :ok = Files.delete("inbox/keep.txt")
    assert :ok = Files.delete("inbox")
    assert {:error, :not_found} = Files.delete("inbox/ghost.txt")
  end

  test "the sandbox root itself cannot be deleted" do
    assert {:error, "Cannot delete the data root"} = Files.delete("")
  end

  # ── mkdir ─────────────────────────────────────────────────────────────────────

  test "mkdir/2 creates a new folder and reports its relative path" do
    assert {:ok, "inbox/nova"} = Files.mkdir("inbox", "nova")

    assert File.dir?(
             Path.join(Application.get_env(:cartograph_backend, :step_data_root), "inbox/nova")
           )

    assert {:ok, [%{name: "nova", isDir: true} | _]} = Files.list("inbox")
  end

  test "mkdir/2 rejects invalid names and separators" do
    for bad <- ["", ".", "..", "a/b", "a\\b", "../evil"] do
      assert {:error, "Invalid folder name"} = Files.mkdir("", bad),
             "mkdir(#{inspect(bad)}) accepted"
    end
  end

  test "mkdir/2 refuses existing entries, missing parents and escapes" do
    assert {:error, "An entry with this name already exists"} = Files.mkdir("", "inbox")
    assert {:error, "An entry with this name already exists"} = Files.mkdir("", "readme.txt")
    assert {:error, :not_found} = Files.mkdir("ghost", "x")
    assert {:error, msg} = Files.mkdir("..", "x")
    assert msg =~ "outside the allowed data directory"
  end
end
