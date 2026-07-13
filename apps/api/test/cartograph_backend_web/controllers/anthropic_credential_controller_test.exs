defmodule CartographBackendWeb.AnthropicCredentialControllerTest do
  use CartographBackendWeb.ConnCase, async: true

  alias CartographBackend.Accounts.{Membership, User}
  alias CartographBackend.Agents
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Repo

  @api_key "sk-ant-api03-abcdef123456"

  setup %{conn: conn} do
    group = %Group{} |> Group.changeset(%{name: "infra"}) |> Repo.insert!()

    project =
      %Project{} |> Project.changeset(%{name: "Linux", group_id: group.id}) |> Repo.insert!()

    other =
      %Project{} |> Project.changeset(%{name: "Outro", group_id: group.id}) |> Repo.insert!()

    viewer = insert_user("viewer")
    explorer = insert_user("explorer")
    navigator = insert_user("navigator")
    outsider = insert_user("outsider")

    grant(viewer, "project", project.id, 10)
    grant(explorer, "project", project.id, 30)
    grant(navigator, "project", project.id, 40)

    {:ok, credential} =
      Agents.create(%{"name" => "main", "api_key" => @api_key, "project_id" => project.id})

    %{
      conn: conn,
      project: project,
      other: other,
      viewer: viewer,
      explorer: explorer,
      navigator: navigator,
      outsider: outsider,
      credential: credential
    }
  end

  defp insert_user(name) do
    %User{}
    |> User.changeset(%{name: name, email: "#{name}@ex.com", password: "secret123"})
    |> Repo.insert!()
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

  # ── index ─────────────────────────────────────────────────────────────────────

  test "a viewer lists name and code but never the API key", %{
    conn: conn,
    viewer: viewer,
    project: p,
    credential: c
  } do
    assert [only] =
             conn
             |> as(viewer)
             |> get("/api/projects/#{p.id}/anthropic-credentials")
             |> json_response(200)

    assert only["name"] == "main"
    assert only["code"] == c.code
    refute Map.has_key?(only, "apiKey")
    refute Map.has_key?(only, "apiKeyEncrypted")
  end

  test "a non-member cannot list", %{conn: conn, outsider: outsider, project: p} do
    assert conn
           |> as(outsider)
           |> get("/api/projects/#{p.id}/anthropic-credentials")
           |> json_response(403)
  end

  # ── create ────────────────────────────────────────────────────────────────────

  test "Navigator creates; the response carries the generated code, not the key", %{
    conn: conn,
    navigator: navigator,
    project: p
  } do
    payload = %{"credential" => %{"name" => "reviewer", "apiKey" => @api_key}}

    res =
      conn
      |> as(navigator)
      |> post("/api/projects/#{p.id}/anthropic-credentials", payload)
      |> json_response(201)

    assert res["code"] =~ ~r/^anthropic-[A-Za-z0-9]{8}$/
    refute Map.has_key?(res, "apiKey")
  end

  test "Explorer (30) cannot create", %{conn: conn, explorer: explorer, project: p} do
    payload = %{"credential" => %{"name" => "reviewer", "apiKey" => @api_key}}

    assert conn
           |> as(explorer)
           |> post("/api/projects/#{p.id}/anthropic-credentials", payload)
           |> json_response(403)
  end

  test "a key that is not an Anthropic key is rejected", %{
    conn: conn,
    navigator: navigator,
    project: p
  } do
    payload = %{"credential" => %{"name" => "reviewer", "apiKey" => "hunter2"}}

    assert conn
           |> as(navigator)
           |> post("/api/projects/#{p.id}/anthropic-credentials", payload)
           |> json_response(422)
  end

  test "creating without a key is rejected", %{conn: conn, navigator: navigator, project: p} do
    assert conn
           |> as(navigator)
           |> post("/api/projects/#{p.id}/anthropic-credentials", %{
             "credential" => %{"name" => "reviewer"}
           })
           |> json_response(422)
  end

  # ── update / delete ───────────────────────────────────────────────────────────

  test "Navigator renames keeping code and stored key", %{
    conn: conn,
    navigator: navigator,
    project: p,
    credential: c
  } do
    payload = %{"credential" => %{"name" => "renamed", "apiKey" => ""}}

    res =
      conn
      |> as(navigator)
      |> put("/api/projects/#{p.id}/anthropic-credentials/#{c.id}", payload)
      |> json_response(200)

    assert res["name"] == "renamed"
    assert res["code"] == c.code

    {:ok, reloaded} = Agents.get(c.id)
    assert reloaded.api_key_encrypted == c.api_key_encrypted
  end

  test "a credential of another project is 404 through this project's route", %{
    conn: conn,
    navigator: navigator,
    other: other,
    credential: c
  } do
    # even with Navigator on `other`, c belongs to `project` → absent, not forbidden
    grant(navigator, "project", other.id, 40)

    assert conn
           |> as(navigator)
           |> put("/api/projects/#{other.id}/anthropic-credentials/#{c.id}", %{
             "credential" => %{"name" => "x"}
           })
           |> json_response(404)
  end

  test "Navigator deletes; Explorer cannot", %{
    conn: conn,
    navigator: navigator,
    explorer: explorer,
    project: p,
    credential: c
  } do
    assert conn
           |> as(explorer)
           |> delete("/api/projects/#{p.id}/anthropic-credentials/#{c.id}")
           |> json_response(403)

    assert conn
           |> as(navigator)
           |> delete("/api/projects/#{p.id}/anthropic-credentials/#{c.id}")
           |> response(204)

    assert [] = Agents.list_for_project(p.id)
  end
end
