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

    # Each project's files live in its own sandbox; paths are relative to it.
    File.mkdir_p!(Path.join(tmp, "projects/#{project.id}"))
    File.write!(Path.join(tmp, "projects/#{project.id}/doc.txt"), "conteudo")
    File.mkdir_p!(Path.join(tmp, "projects/#{other.id}"))
    File.write!(Path.join(tmp, "projects/#{other.id}/secret.txt"), "nope")

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

  # ── Reading a project's files ─────────────────────────────────────────────────

  test "admin lists any project's files with write access", %{
    conn: conn,
    admin: admin,
    project: project
  } do
    res = conn |> as(admin) |> get(~p"/api/projects/#{project.id}/files") |> json_response(200)

    assert res["canWrite"] == true
    assert [%{"name" => "doc.txt"}] = res["entries"]
  end

  test "viewer (10) can list and download but not upload, mkdir or delete", %{
    conn: conn,
    viewer: viewer,
    project: project
  } do
    res = conn |> as(viewer) |> get(~p"/api/projects/#{project.id}/files") |> json_response(200)
    assert res["canWrite"] == false
    assert [%{"name" => "doc.txt"}] = res["entries"]

    dl = conn |> as(viewer) |> get(~p"/api/projects/#{project.id}/files/download?path=doc.txt")
    assert dl.status == 200
    assert dl.resp_body == "conteudo"

    up =
      conn
      |> as(viewer)
      |> post(~p"/api/projects/#{project.id}/files", %{"file" => upload("x", "x.txt")})

    assert up.status == 403

    mk =
      conn
      |> as(viewer)
      |> post(~p"/api/projects/#{project.id}/files/mkdir", %{"name" => "nope"})

    assert mk.status == 403

    del = conn |> as(viewer) |> delete(~p"/api/projects/#{project.id}/files?path=doc.txt")
    assert del.status == 403
  end

  test "editor (30) can upload, mkdir and delete in their project", %{
    conn: conn,
    editor: editor,
    project: project,
    tmp: tmp
  } do
    res = conn |> as(editor) |> get(~p"/api/projects/#{project.id}/files") |> json_response(200)
    assert res["canWrite"] == true

    up =
      conn
      |> as(editor)
      |> post(~p"/api/projects/#{project.id}/files", %{"file" => upload("novo", "novo.txt")})

    assert %{"path" => "novo.txt"} = json_response(up, 201)
    assert File.read!(Path.join(tmp, "projects/#{project.id}/novo.txt")) == "novo"

    mk =
      conn
      |> as(editor)
      |> post(~p"/api/projects/#{project.id}/files/mkdir", %{"name" => "reports"})

    assert %{"path" => "reports"} = json_response(mk, 201)
    assert File.dir?(Path.join(tmp, "projects/#{project.id}/reports"))

    del = conn |> as(editor) |> delete(~p"/api/projects/#{project.id}/files?path=novo.txt")
    assert del.status == 204
  end

  # ── Isolation ─────────────────────────────────────────────────────────────────

  test "a member cannot reach another project's files", %{
    conn: conn,
    editor: editor,
    other: other
  } do
    assert conn |> as(editor) |> get(~p"/api/projects/#{other.id}/files") |> Map.get(:status) ==
             403

    dl = conn |> as(editor) |> get(~p"/api/projects/#{other.id}/files/download?path=secret.txt")
    assert dl.status == 403
  end

  test "an outsider is forbidden", %{conn: conn, outsider: outsider, project: project} do
    assert conn |> as(outsider) |> get(~p"/api/projects/#{project.id}/files") |> Map.get(:status) ==
             403
  end

  test "nonexistent project id is forbidden, not 404 (no enumeration oracle)", %{
    conn: conn,
    editor: editor
  } do
    assert conn |> as(editor) |> get(~p"/api/projects/999999/files") |> Map.get(:status) == 403
  end

  test "paths escaping the project sandbox are rejected (400)", %{
    conn: conn,
    editor: editor,
    project: project
  } do
    res = conn |> as(editor) |> get(~p"/api/projects/#{project.id}/files?path=..")
    assert res.status == 400
  end

  # ── mkdir validation ──────────────────────────────────────────────────────────

  test "bad folder names are 400, missing name is 400", %{
    conn: conn,
    editor: editor,
    project: project
  } do
    res =
      conn |> as(editor) |> post(~p"/api/projects/#{project.id}/files/mkdir", %{"name" => "a/b"})

    assert json_response(res, 400)["error"] == "Invalid folder name"

    res = conn |> as(editor) |> post(~p"/api/projects/#{project.id}/files/mkdir", %{})
    assert json_response(res, 400)["error"] == "Missing name"
  end

  test "missing file upload is 400", %{conn: conn, editor: editor, project: project} do
    res = conn |> as(editor) |> post(~p"/api/projects/#{project.id}/files", %{})
    assert json_response(res, 400)["error"] == "Missing file"
  end

  # ── Lazy provisioning ─────────────────────────────────────────────────────────

  test "a project sandbox is created on first authorized access", %{
    conn: conn,
    tmp: tmp,
    editor: editor,
    project: project
  } do
    File.rm_rf!(Path.join(tmp, "projects/#{project.id}"))

    res = conn |> as(editor) |> get(~p"/api/projects/#{project.id}/files") |> json_response(200)
    assert res["entries"] == []
    assert File.dir?(Path.join(tmp, "projects/#{project.id}"))
  end
end
