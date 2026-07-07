defmodule CartographBackendWeb.FileControllerTest do
  # NOT async: overrides the global :step_data_root sandbox for each test.
  use CartographBackendWeb.ConnCase, async: false

  alias CartographBackend.Accounts.{Membership, User}
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Repo

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp, conn: conn} do
    previous = Application.get_env(:cartograph_backend, :step_data_root)
    Application.put_env(:cartograph_backend, :step_data_root, tmp)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cartograph_backend, :step_data_root, previous),
        else: Application.delete_env(:cartograph_backend, :step_data_root)
    end)

    group = %Group{} |> Group.changeset(%{name: "infra"}) |> Repo.insert!()

    project =
      %Project{} |> Project.changeset(%{name: "Linux", group_id: group.id}) |> Repo.insert!()

    other =
      %Project{} |> Project.changeset(%{name: "Outro", group_id: group.id}) |> Repo.insert!()

    File.mkdir_p!(Path.join(tmp, "inbox"))
    File.write!(Path.join(tmp, "inbox/global.txt"), "global")
    File.mkdir_p!(Path.join(tmp, "projects/#{project.id}"))
    File.write!(Path.join(tmp, "projects/#{project.id}/doc.txt"), "conteudo")

    admin = insert_user("admin", is_admin: true)
    viewer = insert_user("viewer")
    editor = insert_user("editor")
    outsider = insert_user("outsider")

    grant(viewer, "project", project.id, 10)
    grant(editor, "project", project.id, 30)

    %{
      conn: conn,
      tmp: tmp,
      project: project,
      other: other,
      admin: admin,
      viewer: viewer,
      editor: editor,
      outsider: outsider
    }
  end

  defp insert_user(name, opts \\ []) do
    user =
      %User{}
      |> User.changeset(%{name: name, email: "#{name}@ex.com", password: "secret123"})
      |> Repo.insert!()

    if opts[:is_admin],
      do: user |> Ecto.Changeset.change(is_admin: true) |> Repo.update!(),
      else: user
  end

  defp grant(user, type, id, level) do
    %Membership{}
    |> Membership.changeset(%{
      user_id: user.id,
      subject_type: type,
      subject_id: id,
      access_level: level
    })
    |> Repo.insert!()
  end

  defp as(conn, user) do
    token = Phoenix.Token.sign(CartographBackendWeb.Endpoint, "user auth", user.id)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp upload(content, filename) do
    tmp = Path.join(System.tmp_dir!(), "up-#{System.unique_integer([:positive])}")
    File.write!(tmp, content)
    %Plug.Upload{path: tmp, filename: filename, content_type: "application/octet-stream"}
  end

  # ── Admin (unchanged v1 behavior) ─────────────────────────────────────────────

  test "admin lists the real root with write access", %{conn: conn, admin: admin} do
    res = conn |> as(admin) |> get(~p"/api/files") |> json_response(200)

    assert res["canWrite"] == true
    assert Enum.any?(res["entries"], &(&1["name"] == "inbox"))
    assert Enum.any?(res["entries"], &(&1["name"] == "projects"))
  end

  # ── Non-admin root: virtual project folders ───────────────────────────────────

  test "member's root listing shows only their projects, by name", %{
    conn: conn,
    viewer: viewer,
    project: project
  } do
    res = conn |> as(viewer) |> get(~p"/api/files") |> json_response(200)

    assert res["canWrite"] == false
    assert [entry] = res["entries"]
    assert %{"name" => "Linux", "isDir" => true} = entry
    assert entry["path"] == "projects/#{project.id}"
  end

  test "outsider's root listing is empty", %{conn: conn, outsider: outsider} do
    assert %{"entries" => []} = conn |> as(outsider) |> get(~p"/api/files") |> json_response(200)
  end

  # ── Membership enforcement inside a project ───────────────────────────────────

  test "viewer (10) can list and download but not upload or delete", %{
    conn: conn,
    viewer: viewer,
    project: project
  } do
    base = "projects/#{project.id}"
    doc = "#{base}/doc.txt"

    res = conn |> as(viewer) |> get(~p"/api/files?path=#{base}") |> json_response(200)
    assert res["canWrite"] == false
    assert [%{"name" => "doc.txt"}] = res["entries"]

    dl = conn |> as(viewer) |> get(~p"/api/files/download?path=#{doc}")
    assert dl.status == 200
    assert dl.resp_body == "conteudo"

    up =
      conn
      |> as(viewer)
      |> post(~p"/api/files", %{"file" => upload("x", "x.txt"), "path" => base})

    assert up.status == 403

    del = conn |> as(viewer) |> delete(~p"/api/files?path=#{doc}")
    assert del.status == 403
  end

  test "editor (30) can upload and delete in their project", %{
    conn: conn,
    editor: editor,
    project: project,
    tmp: tmp
  } do
    base = "projects/#{project.id}"

    res = conn |> as(editor) |> get(~p"/api/files?path=#{base}") |> json_response(200)
    assert res["canWrite"] == true

    up =
      conn
      |> as(editor)
      |> post(~p"/api/files", %{"file" => upload("novo", "novo.txt"), "path" => base})

    assert %{"path" => path} = json_response(up, 201)
    assert path == "#{base}/novo.txt"
    assert File.read!(Path.join(tmp, path)) == "novo"

    del = conn |> as(editor) |> delete(~p"/api/files?path=#{path}")
    assert del.status == 204
  end

  test "a member cannot reach global dirs or other projects", %{
    conn: conn,
    editor: editor,
    other: other
  } do
    for path <- ["inbox", "inbox/global.txt", "projects/#{other.id}", "projects", "no-such"] do
      assert conn |> as(editor) |> get(~p"/api/files?path=#{path}") |> Map.get(:status) == 403,
             "list(#{path}) should be forbidden"
    end

    dl = conn |> as(editor) |> get(~p"/api/files/download?path=inbox/global.txt")
    assert dl.status == 403
  end

  test "nonexistent project id is forbidden, not 404 (no enumeration oracle)", %{
    conn: conn,
    editor: editor
  } do
    assert conn |> as(editor) |> get(~p"/api/files?path=projects/999999") |> Map.get(:status) ==
             403
  end

  # ── mkdir ─────────────────────────────────────────────────────────────────────

  test "editor (30) can create a folder in their project; viewer (10) cannot", %{
    conn: conn,
    editor: editor,
    viewer: viewer,
    project: project,
    tmp: tmp
  } do
    base = "projects/#{project.id}"

    res = conn |> as(editor) |> post(~p"/api/files/mkdir", %{"path" => base, "name" => "inbox"})
    assert %{"path" => path} = json_response(res, 201)
    assert path == "#{base}/inbox"
    assert File.dir?(Path.join(tmp, path))

    res = conn |> as(viewer) |> post(~p"/api/files/mkdir", %{"path" => base, "name" => "nope"})
    assert res.status == 403
  end

  test "admin can create folders anywhere; bad names are 400", %{conn: conn, admin: admin} do
    res = conn |> as(admin) |> post(~p"/api/files/mkdir", %{"path" => "", "name" => "relatorios"})
    assert %{"path" => "relatorios"} = json_response(res, 201)

    res = conn |> as(admin) |> post(~p"/api/files/mkdir", %{"path" => "", "name" => "a/b"})
    assert json_response(res, 400)["error"] == "Invalid folder name"

    res = conn |> as(admin) |> post(~p"/api/files/mkdir", %{"path" => ""})
    assert json_response(res, 400)["error"] == "Missing name"
  end

  test "member cannot mkdir at the virtual root or in foreign dirs", %{
    conn: conn,
    editor: editor,
    other: other
  } do
    for path <- ["", "inbox", "projects/#{other.id}"] do
      res = conn |> as(editor) |> post(~p"/api/files/mkdir", %{"path" => path, "name" => "x"})
      assert res.status == 403, "mkdir in #{inspect(path)} should be forbidden"
    end
  end

  # ── Lazy provisioning ─────────────────────────────────────────────────────────

  test "a project dir is created on first authorized access", %{
    conn: conn,
    tmp: tmp,
    editor: editor,
    project: project
  } do
    base = "projects/#{project.id}"
    File.rm_rf!(Path.join(tmp, base))

    res = conn |> as(editor) |> get(~p"/api/files?path=#{base}") |> json_response(200)
    assert res["entries"] == []
    assert File.dir?(Path.join(tmp, base))
  end
end
