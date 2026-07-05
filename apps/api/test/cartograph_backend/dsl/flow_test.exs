defmodule CartographBackend.Dsl.FlowTest do
  use CartographBackend.DataCase, async: true

  alias CartographBackend.Dsl.Flow
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Tasks.TaskDefinition
  alias CartographBackend.Accounts.{User, Membership}

  defp insert_group(name), do: %Group{} |> Group.changeset(%{name: name}) |> Repo.insert!()

  defp insert_project(name, gid),
    do: %Project{} |> Project.changeset(%{name: name, group_id: gid}) |> Repo.insert!()

  defp insert_task(name, dsl, attrs \\ %{}) do
    identifier = attrs[:identifier] || (name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-"))

    %TaskDefinition{}
    |> TaskDefinition.changeset(Map.merge(%{name: name, identifier: identifier, dsl: dsl}, attrs))
    |> Repo.insert!()
  end

  defp insert_user(name),
    do:
      %User{}
      |> User.changeset(%{name: name, email: "#{name}@ex.com", password: "secret123"})
      |> Repo.insert!()

  defp grant(user, type, id, level) do
    %Membership{}
    |> Membership.changeset(%{user_id: user.id, subject_type: type, subject_id: id, access_level: level})
    |> Repo.insert!()
  end

  test "plain steps become step nodes in order" do
    assert {:ok, nodes} = Flow.build(~s|t { step "a" step "b" }|, :system)

    assert [
             %{"kind" => "step", "name" => "a"},
             %{"kind" => "step", "name" => "b"}
           ] = nodes
  end

  test "a `use` ref is inlined as a job group preserving the sub-job's own steps" do
    g = insert_group("g")
    p = insert_project("p", g.id)
    sub = insert_task("backup", ~s|backup { step "inner1" step "inner2" }|, %{project_id: p.id})

    user = insert_user("alice")
    grant(user, "group", g.id, 10)

    {:ok, nodes} =
      Flow.build(~s|caller { step "a" use "#{sub.code}" step "b" }|, %{user: user})

    assert [
             %{"kind" => "step", "name" => "a"},
             %{"kind" => "job", "ref" => ref, "name" => "backup", "cycle" => false, "steps" => inner},
             %{"kind" => "step", "name" => "b"}
           ] = nodes

    assert ref == sub.code
    assert [%{"kind" => "step", "name" => "inner1"}, %{"kind" => "step", "name" => "inner2"}] = inner
  end

  test "unauthorized / nonexistent ref becomes a job_error node (build still succeeds)" do
    g = insert_group("g")
    p = insert_project("p", g.id)
    secret = insert_task("secret", ~s|s { step "x" }|, %{project_id: p.id})

    user = insert_user("nobody")

    {:ok, nodes} = Flow.build(~s|caller { use "#{secret.code}" use "ghost-00000000" }|, %{user: user})

    assert [%{"kind" => "job_error"}, %{"kind" => "job_error"}] = nodes
  end

  test "if/else renders both branches with a readable condition" do
    {:ok, nodes} =
      Flow.build(~s|t { if state["count"] > 5 { step "big" } else { step "small" } }|, :system)

    assert [%{"kind" => "if", "condition" => cond, "then" => then_b, "else" => else_b}] = nodes
    assert cond == ~s(state["count"] > 5)
    assert [%{"kind" => "step", "name" => "big"}] = then_b
    assert [%{"kind" => "step", "name" => "small"}] = else_b
  end

  test "self-reference cycle is shown once, not expanded infinitely" do
    g = insert_group("g")
    p = insert_project("p", g.id)
    loop = insert_task("loop", ~s|loop { step "noop" }|, %{project_id: p.id})

    loop =
      loop
      |> TaskDefinition.update_changeset(%{dsl: ~s|loop { step "noop" use "#{loop.code}" }|})
      |> Repo.update!()

    {:ok, nodes} = Flow.build(loop.dsl, :system, loop.code)

    assert [
             %{"kind" => "step", "name" => "noop"},
             %{"kind" => "job", "cycle" => true, "steps" => []}
           ] = nodes
  end

  test "invalid top-level DSL returns an error" do
    assert {:error, _} = Flow.build(~s|not valid {{{|, :system)
  end

  test "every node carries a stable structural id (path-based, deterministic)" do
    g = insert_group("g")
    p = insert_project("p", g.id)
    sub = insert_task("sub", ~s|sub { step "inner" }|, %{project_id: p.id})

    dsl = ~s|t { step "a" if state["x"] { step "b" } else { step "c" } use "#{sub.code}" }|

    {:ok, nodes} = Flow.build(dsl, :system)
    {:ok, again} = Flow.build(dsl, :system)
    assert nodes == again, "ids must be deterministic for the same DSL"

    assert [
             %{"id" => "0", "kind" => "step"},
             %{"id" => "1", "kind" => "if", "then" => [%{"id" => "1/t0"}], "else" => [%{"id" => "1/e0"}]},
             %{"id" => "2", "kind" => "job", "steps" => [%{"id" => "2/j0", "kind" => "step", "name" => "inner"}]}
           ] = nodes
  end
end
