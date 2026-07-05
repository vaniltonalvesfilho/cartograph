defmodule CartographBackend.Tasks.Graph do
  @moduledoc """
  Cross-job reference graph: nodes are the tasks the caller passes in (already
  filtered to what the viewer may see), edges are `use`/`job` refs between
  them. A ref to a job outside that set produces no edge — same
  no-enumeration-oracle rule as `RefResolver`.

  Each node carries its project/group for visual grouping and an `inCycle`
  flag. Cycles can't be saved through the API (the Expander rejects them at
  validation), so the flag only fires on data that bypassed it — but the graph
  must stay honest about what is actually stored.
  """

  alias CartographBackend.Dsl.Refs
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Repo

  @spec build([struct()]) :: %{nodes: [map()], edges: [map()]}
  def build(tasks) do
    by_code = Map.new(tasks, &{&1.code, &1.id})

    edges =
      for t <- tasks,
          code <- Refs.extract(t.dsl),
          target = by_code[code],
          target != nil,
          uniq: true,
          do: {t.id, target}

    projects = Repo.all(Project) |> Map.new(&{&1.id, &1})
    groups = Repo.all(Group) |> Map.new(&{&1.id, &1})
    cyclic = cyclic_ids(edges)

    %{
      nodes:
        Enum.map(tasks, fn t ->
          project = projects[t.project_id]
          group = project && groups[project.group_id]

          %{
            id: t.id,
            name: t.name,
            code: t.code,
            cron: t.cron,
            projectId: project && project.id,
            projectName: project && project.name,
            groupId: group && group.id,
            groupName: group && group.name,
            inCycle: MapSet.member?(cyclic, t.id)
          }
        end),
      edges: Enum.map(edges, fn {source, target} -> %{source: source, target: target} end)
    }
  end

  # A node is on a cycle iff it can reach itself. O(V·E) DFS per node — fine
  # for the few hundred jobs an instance realistically holds.
  defp cyclic_ids(edges) do
    adjacency = Enum.group_by(edges, &elem(&1, 0), &elem(&1, 1))

    adjacency
    |> Map.keys()
    |> Enum.filter(&reaches?(adjacency, Map.fetch!(adjacency, &1), &1, MapSet.new()))
    |> MapSet.new()
  end

  defp reaches?(_adjacency, [], _goal, _seen), do: false

  defp reaches?(adjacency, [node | rest], goal, seen) do
    cond do
      node == goal -> true
      MapSet.member?(seen, node) -> reaches?(adjacency, rest, goal, seen)
      true -> reaches?(adjacency, Map.get(adjacency, node, []) ++ rest, goal, MapSet.put(seen, node))
    end
  end
end
