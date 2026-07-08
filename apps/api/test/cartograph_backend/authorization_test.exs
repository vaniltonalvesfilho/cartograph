defmodule CartographBackend.AuthorizationTest do
  # DB-backed: authorization cascades through the group → project → task hierarchy
  # via membership rows.
  use CartographBackend.DataCase, async: true

  alias CartographBackend.Authorization
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Tasks.TaskDefinition
  alias CartographBackend.Accounts.{User, Membership}

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp insert_group(name, parent_id \\ nil) do
    %Group{} |> Group.changeset(%{name: name, parent_id: parent_id}) |> Repo.insert!()
  end

  defp insert_project(name, group_id) do
    %Project{} |> Project.changeset(%{name: name, group_id: group_id}) |> Repo.insert!()
  end

  defp insert_task(name, project_id) do
    %TaskDefinition{}
    |> TaskDefinition.changeset(%{
      name: name,
      identifier: String.downcase(name),
      dsl: ~s|#{String.downcase(name)} { step "a" }|,
      project_id: project_id
    })
    |> Repo.insert!()
  end

  defp insert_user(name, attrs \\ %{}) do
    %User{}
    |> User.changeset(
      Map.merge(%{name: name, email: "#{name}@ex.com", password: "secret123"}, attrs)
    )
    |> User.admin_changeset(attrs)
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

  # Hierarchy shared by most tests: group → subgroup → project → task.
  defp hierarchy do
    g = insert_group("root")
    sg = insert_group("sub", g.id)
    p = insert_project("proj", sg.id)
    t = insert_task("job", p.id)
    %{g: g, sg: sg, p: p, t: t}
  end

  # ── effective_level/2 ─────────────────────────────────────────────────────────

  test "a group membership cascades down to descendant subgroup, project and task" do
    %{g: g, sg: sg, p: p, t: t} = hierarchy()
    user = insert_user("alice")
    grant(user, "group", g.id, 30)

    assert Authorization.effective_level(user, g) == 30
    assert Authorization.effective_level(user, sg) == 30
    assert Authorization.effective_level(user, p) == 30
    assert Authorization.effective_level(user, t) == 30
  end

  test "a more specific membership overrides the inherited level by taking the max" do
    %{g: g, sg: sg, p: p, t: t} = hierarchy()
    user = insert_user("bob")
    grant(user, "group", g.id, 20)
    grant(user, "project", p.id, 40)

    assert Authorization.effective_level(user, sg) == 20
    assert Authorization.effective_level(user, p) == 40
    assert Authorization.effective_level(user, t) == 40
  end

  test "a direct task membership combines with the inherited project level (max)" do
    %{p: p, t: t} = hierarchy()
    user = insert_user("carol")
    grant(user, "project", p.id, 10)
    grant(user, "task", t.id, 30)

    assert Authorization.effective_level(user, t) == 30
  end

  test "no membership yields level 0; a global admin is always 50; nil user is 0" do
    %{g: g, t: t} = hierarchy()
    stranger = insert_user("dan")
    admin = insert_user("eve", %{is_admin: true})

    assert Authorization.effective_level(stranger, g) == 0
    assert Authorization.effective_level(stranger, t) == 0
    assert Authorization.effective_level(admin, g) == 50
    assert Authorization.effective_level(admin, t) == 50
    assert Authorization.effective_level(nil, g) == 0
  end

  # ── scope/1 ───────────────────────────────────────────────────────────────────

  test "scope includes accessible resources at their level plus ancestors for navigation" do
    %{g: g, sg: sg, p: p, t: t} = hierarchy()
    user = insert_user("frank")
    grant(user, "project", p.id, 40)

    scope = Authorization.scope(user)

    assert scope.projects[p.id] == 40
    assert scope.tasks[t.id] == 40
    # Ancestor groups are present (for the nav tree) even without a membership.
    assert Map.has_key?(scope.groups, sg.id)
    assert Map.has_key?(scope.groups, g.id)
  end

  test "scope and effective_level agree on the level of an accessible resource" do
    %{g: g, p: p, t: t} = hierarchy()
    user = insert_user("grace")
    grant(user, "group", g.id, 30)

    scope = Authorization.scope(user)

    assert scope.tasks[t.id] == Authorization.effective_level(user, t)
    assert scope.projects[p.id] == Authorization.effective_level(user, p)
  end
end
