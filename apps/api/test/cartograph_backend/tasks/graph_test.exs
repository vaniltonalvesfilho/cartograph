defmodule CartographBackend.Tasks.GraphTest do
  # DB-backed: Graph.build reads projects/groups for node grouping.
  use CartographBackend.DataCase, async: true

  alias CartographBackend.Dsl.Refs
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Tasks.Graph
  alias CartographBackend.Tasks.TaskDefinition

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp insert_group(name) do
    %Group{} |> Group.changeset(%{name: name}) |> Repo.insert!()
  end

  defp insert_project(name, group_id) do
    %Project{} |> Project.changeset(%{name: name, group_id: group_id}) |> Repo.insert!()
  end

  defp insert_task(name, dsl, attrs \\ %{}) do
    identifier = attrs[:identifier] || slug(name)

    %TaskDefinition{}
    |> TaskDefinition.changeset(Map.merge(%{name: name, identifier: identifier, dsl: dsl}, attrs))
    |> Repo.insert!()
  end

  defp slug(name), do: name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")

  # Rewrites a stored DSL bypassing API validation — how a cycle gets into the DB.
  defp force_dsl!(task, dsl) do
    task |> TaskDefinition.update_changeset(%{dsl: dsl}) |> Repo.update!()
  end

  # ── Refs.extract ──────────────────────────────────────────────────────────────

  test "extract finds use and job refs in source order, deduplicated" do
    dsl = ~s|t { use "a-11111111" step "x" job "b-22222222" use "a-11111111" }|
    assert Refs.extract(dsl) == ["a-11111111", "b-22222222"]
  end

  test "extract walks if/else branches, nested" do
    dsl =
      ~s|t { if state["k"] { use "a-11111111" if state["j"] { use "b-22222222" } } else { use "c-33333333" } }|

    assert Refs.extract(dsl) == ["a-11111111", "b-22222222", "c-33333333"]
  end

  test "extract returns [] for unparsable or empty DSL" do
    assert Refs.extract("not a dsl {{{") == []
    assert Refs.extract("") == []
    assert Refs.extract(nil) == []
  end

  # ── Graph.build ───────────────────────────────────────────────────────────────

  test "nodes carry project/group; edges only between the given tasks" do
    g = insert_group("infra")
    p = insert_project("linux", g.id)
    target = insert_task("backup", ~s|backup { step "s" }|, %{project_id: p.id})

    caller =
      insert_task("caller", ~s|caller { use "#{target.code}" use "ghost-00000000" }|, %{
        project_id: p.id
      })

    orphan = insert_task("alone", ~s|alone { step "s" }|)

    %{nodes: nodes, edges: edges} = Graph.build([target, caller, orphan])

    caller_node = Enum.find(nodes, &(&1.id == caller.id))
    assert %{projectId: pid, projectName: "linux", groupId: gid, groupName: "infra"} = caller_node
    assert pid == p.id and gid == g.id
    refute caller_node.inCycle

    orphan_node = Enum.find(nodes, &(&1.id == orphan.id))
    assert %{projectId: nil, projectName: nil, groupId: nil, groupName: nil} = orphan_node

    # the ghost ref produced no edge
    assert edges == [%{source: caller.id, target: target.id}]
  end

  test "edges to visible-but-unlisted tasks are omitted" do
    hidden = insert_task("hidden", ~s|hidden { step "s" }|)
    caller = insert_task("caller", ~s|caller { use "#{hidden.code}" }|)

    assert %{edges: []} = Graph.build([caller])
  end

  test "tasks on a reference cycle are marked inCycle; bystanders are not" do
    a = insert_task("job-a", ~s|a { step "s" }|)
    b = insert_task("job-b", ~s|b { use "#{a.code}" }|)
    a = force_dsl!(a, ~s|a { use "#{b.code}" }|)
    watcher = insert_task("watcher", ~s|w { use "#{a.code}" }|)

    %{nodes: nodes} = Graph.build([a, b, watcher])
    by_id = Map.new(nodes, &{&1.id, &1})

    assert by_id[a.id].inCycle
    assert by_id[b.id].inCycle
    refute by_id[watcher.id].inCycle
  end

  test "self-reference is a cycle" do
    t = insert_task("selfie", ~s|s { step "s" }|)
    t = force_dsl!(t, ~s|s { use "#{t.code}" }|)

    %{nodes: [node], edges: [edge]} = Graph.build([t])
    assert node.inCycle
    assert edge == %{source: t.id, target: t.id}
  end
end
