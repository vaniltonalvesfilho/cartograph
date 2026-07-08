defmodule CartographBackend.Groups do
  import Ecto.Query
  alias CartographBackend.Repo
  alias CartographBackend.Groups.{Group, Project}

  # ── Groups ────────────────────────────────────────────────────────────────────

  def list_groups do
    Repo.all(
      from g in Group,
        order_by: [asc: fragment("COALESCE(?, 0)", g.parent_id), asc: g.position, asc: g.id]
    )
  end

  def get_group(id) do
    case Repo.get(Group, id) do
      nil -> {:error, :not_found}
      group -> {:ok, group}
    end
  end

  def create_group(attrs) do
    %Group{}
    |> Group.changeset(attrs)
    |> Repo.insert()
  end

  def update_group(id, attrs) do
    with {:ok, group} <- get_group(id) do
      new_parent_id = Map.get(attrs, "parent_id") || Map.get(attrs, :parent_id)

      if new_parent_id && cycle?(id, new_parent_id) do
        {:error, :cycle_detected}
      else
        group
        |> Group.changeset(attrs)
        |> Repo.update()
      end
    end
  end

  def delete_group(id) do
    with {:ok, group} <- get_group(id) do
      Repo.delete(group)
    end
  end

  # ── Projects ──────────────────────────────────────────────────────────────────

  def list_projects(opts \\ []) do
    query = from p in Project, order_by: [asc: p.position, asc: p.id]

    query =
      case Keyword.get(opts, :group_id) do
        nil -> query
        :root -> where(query, [p], is_nil(p.group_id))
        id -> where(query, [p], p.group_id == ^id)
      end

    Repo.all(query)
  end

  def get_project(id) do
    case Repo.get(Project, id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(id, attrs) do
    with {:ok, project} <- get_project(id) do
      project
      |> Project.changeset(attrs)
      |> Repo.update()
    end
  end

  def delete_project(id) do
    with {:ok, project} <- get_project(id) do
      # Nullify project_id on tasks before deleting
      from(t in CartographBackend.Tasks.TaskDefinition, where: t.project_id == ^id)
      |> Repo.update_all(set: [project_id: nil])

      Repo.delete(project)
    end
  end

  # ── Cycle detection ───────────────────────────────────────────────────────────

  defp cycle?(group_id, candidate_parent_id) do
    candidate_parent_id == group_id || ancestor?(candidate_parent_id, group_id)
  end

  defp ancestor?(node_id, target_id) do
    case Repo.get(Group, node_id) do
      nil -> false
      %{parent_id: nil} -> false
      %{parent_id: ^target_id} -> true
      %{parent_id: parent_id} -> ancestor?(parent_id, target_id)
    end
  end
end
