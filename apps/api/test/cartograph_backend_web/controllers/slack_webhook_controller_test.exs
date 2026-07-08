defmodule CartographBackendWeb.SlackWebhookControllerTest do
  use CartographBackendWeb.ConnCase, async: true

  alias CartographBackend.Accounts.{Membership, User}
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Repo
  alias CartographBackend.Webhooks

  @url "https://hooks.slack.com/services/T000/B000/XXXX"

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

    {:ok, webhook} =
      Webhooks.create(%{"name" => "alerts", "url" => @url, "project_id" => project.id})

    %{
      conn: conn,
      project: project,
      other: other,
      viewer: viewer,
      explorer: explorer,
      navigator: navigator,
      outsider: outsider,
      webhook: webhook
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

  test "a viewer lists name and code but never the URL", %{
    conn: conn,
    viewer: viewer,
    project: p,
    webhook: w
  } do
    assert [only] =
             conn
             |> as(viewer)
             |> get("/api/projects/#{p.id}/slack-webhooks")
             |> json_response(200)

    assert only["name"] == "alerts"
    assert only["code"] == w.code
    refute Map.has_key?(only, "url")
  end

  test "a non-member cannot list", %{conn: conn, outsider: outsider, project: p} do
    assert conn
           |> as(outsider)
           |> get("/api/projects/#{p.id}/slack-webhooks")
           |> json_response(403)
  end

  # ── create ────────────────────────────────────────────────────────────────────

  test "Navigator creates; the response carries the generated code, not the URL", %{
    conn: conn,
    navigator: navigator,
    project: p
  } do
    payload = %{"webhook" => %{"name" => "deploys", "url" => @url}}

    res =
      conn
      |> as(navigator)
      |> post("/api/projects/#{p.id}/slack-webhooks", payload)
      |> json_response(201)

    assert res["code"] =~ ~r/^slack-[A-Za-z0-9]{8}$/
    refute Map.has_key?(res, "url")
  end

  test "Explorer (30) cannot create", %{conn: conn, explorer: explorer, project: p} do
    payload = %{"webhook" => %{"name" => "deploys", "url" => @url}}

    assert conn
           |> as(explorer)
           |> post("/api/projects/#{p.id}/slack-webhooks", payload)
           |> json_response(403)
  end

  test "a non-Slack URL is rejected", %{conn: conn, navigator: navigator, project: p} do
    payload = %{"webhook" => %{"name" => "deploys", "url" => "https://evil.example.com/hook"}}

    assert conn
           |> as(navigator)
           |> post("/api/projects/#{p.id}/slack-webhooks", payload)
           |> json_response(422)
  end

  # ── update / delete ───────────────────────────────────────────────────────────

  test "Navigator renames keeping code and stored URL", %{
    conn: conn,
    navigator: navigator,
    project: p,
    webhook: w
  } do
    payload = %{"webhook" => %{"name" => "renamed", "url" => ""}}

    res =
      conn
      |> as(navigator)
      |> put("/api/projects/#{p.id}/slack-webhooks/#{w.id}", payload)
      |> json_response(200)

    assert res["name"] == "renamed"
    assert res["code"] == w.code
  end

  test "a webhook of another project is 404 through this project's route", %{
    conn: conn,
    navigator: navigator,
    other: other,
    webhook: w
  } do
    # even with Navigator on `other`, w belongs to `project` → absent, not forbidden
    grant(navigator, "project", other.id, 40)

    assert conn
           |> as(navigator)
           |> put("/api/projects/#{other.id}/slack-webhooks/#{w.id}", %{
             "webhook" => %{"name" => "x"}
           })
           |> json_response(404)
  end

  test "Navigator deletes; Explorer cannot", %{
    conn: conn,
    navigator: navigator,
    explorer: explorer,
    project: p,
    webhook: w
  } do
    assert conn
           |> as(explorer)
           |> delete("/api/projects/#{p.id}/slack-webhooks/#{w.id}")
           |> json_response(403)

    assert conn
           |> as(navigator)
           |> delete("/api/projects/#{p.id}/slack-webhooks/#{w.id}")
           |> response(204)

    assert [] = Webhooks.list_for_project(p.id)
  end
end
