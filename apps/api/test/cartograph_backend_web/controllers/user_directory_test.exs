defmodule CartographBackendWeb.UserDirectoryTest do
  @moduledoc """
  CG-10: `/api/users/pickable` used to hand every authenticated account the
  name and email of every user on the instance — a ready-made phishing list
  for the lowest-privileged account there is.
  """
  use CartographBackendWeb.ConnCase, async: true

  alias CartographBackend.Accounts.{Membership, User}
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Repo

  setup %{conn: conn} do
    group = %Group{} |> Group.changeset(%{name: "infra"}) |> Repo.insert!()

    project =
      %Project{} |> Project.changeset(%{name: "Linux", group_id: group.id}) |> Repo.insert!()

    %{conn: conn, project: project}
  end

  defp insert_user(name, attrs \\ %{}) do
    %User{}
    |> User.changeset(%{name: name, email: "#{name}@example.com", password: "secret123"})
    |> User.admin_changeset(attrs)
    |> Repo.insert!()
  end

  defp grant(user, subject_type, subject_id, level) do
    %Membership{}
    |> Membership.changeset(%{
      user_id: user.id,
      subject_type: subject_type,
      subject_id: subject_id,
      access_level: level
    })
    |> Repo.insert!()
  end

  defp as(conn, user) do
    token = Phoenix.Token.sign(CartographBackendWeb.Endpoint, "user auth", user.id)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  test "a read-only member cannot enumerate the directory", %{conn: conn, project: project} do
    wayfarer = insert_user("wayfarer")
    grant(wayfarer, "project", project.id, 10)

    assert conn |> as(wayfarer) |> get(~p"/api/users/pickable") |> json_response(403)
  end

  test "a member with no membership at all cannot either", %{conn: conn} do
    assert conn
           |> as(insert_user("outsider"))
           |> get(~p"/api/users/pickable")
           |> json_response(403)
  end

  test "someone who can manage members can", %{conn: conn, project: project} do
    navigator = insert_user("navigator")
    grant(navigator, "project", project.id, 40)

    assert [_ | _] = conn |> as(navigator) |> get(~p"/api/users/pickable") |> json_response(200)
  end

  test "an admin can", %{conn: conn} do
    admin = insert_user("admin", %{is_admin: true})

    assert [_ | _] = conn |> as(admin) |> get(~p"/api/users/pickable") |> json_response(200)
  end
end
