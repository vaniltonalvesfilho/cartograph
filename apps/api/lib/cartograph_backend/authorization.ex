defmodule CartographBackend.Authorization do
  @moduledoc """
  Central authorization for Cartograph.

  Access is modelled as a single integer level per (user, resource). Levels
  cascade downward through the hierarchy: a membership on a group applies to all
  its descendant groups, projects and tasks. A more specific membership (e.g. on
  the project) overrides by taking the maximum.

      Wayfarer     10  somente leitura
      Scout        20  executar jobs
      Explorer     30  criar/editar jobs
      Navigator    40  gerenciar membros e excluir
      Cartographer 50  controle total (admin global)
  """

  import Ecto.Query
  alias CartographBackend.Repo
  alias CartographBackend.Accounts.Membership
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Tasks.TaskDefinition
  alias CartographBackend.Executions.TaskExecution

  # Single source of truth for access levels (value, display name, description).
  # `@level_names` and the `levels/0` endpoint payload both derive from this.
  @levels [
    %{value: 10, name: "Wayfarer",     description: "Somente leitura"},
    %{value: 20, name: "Scout",        description: "Executar jobs e visualizar"},
    %{value: 30, name: "Explorer",     description: "Criar, editar e executar jobs"},
    %{value: 40, name: "Navigator",    description: "Gerenciar membros e excluir"},
    %{value: 50, name: "Cartographer", description: "Controle total"}
  ]
  @level_names Map.new(@levels, &{&1.value, &1.name})

  @required_level %{
    view:           10,
    run:            20,
    create:         30,
    edit:           30,
    delete:         40,
    manage_members: 40,
    manage_secrets: 40,
    admin:          50
  }

  @doc "Minimum level required for an action."
  def required_level(action), do: Map.fetch!(@required_level, action)

  # ── Permission checks ─────────────────────────────────────────────────────────

  def can?(%{is_admin: true}, _action, _resource), do: true
  def can?(nil, _action, _resource), do: false

  def can?(user, action, resource) do
    effective_level(user, resource) >= Map.fetch!(@required_level, action)
  end

  @doc "Returns :ok or {:error, :forbidden}, convenient for `with` chains."
  def authorize(user, action, resource) do
    if can?(user, action, resource), do: :ok, else: {:error, :forbidden}
  end

  # ── Action policies (shared by REST controllers and GraphQL resolvers) ────────
  #
  # These encode *who may create or move a resource*, as opposed to `authorize/3`
  # which checks an action against an already-loaded resource. They return
  # `:ok | {:error, :forbidden}`; the GraphQL layer maps `:forbidden` to a string.

  @doc """
  Creating a resource requires `:create` on its parent. A nil parent denotes a
  root resource (group with no parent, project with no group, global task),
  which only global admins may create.
  """
  def authorize_create_group(user, parent_group_id), do: require_parent_create(user, Group, parent_group_id)
  def authorize_create_project(user, group_id), do: require_parent_create(user, Group, group_id)
  def authorize_create_task(user, project_id), do: require_parent_create(user, Project, project_id)

  @doc """
  Moving a resource to a new parent requires `:create` on the destination.
  `:unchanged` (the update doesn't touch the parent) and nil (detach to root)
  both pass without a check.
  """
  def authorize_move_project(user, group_id), do: optional_parent_create(user, Group, group_id)
  def authorize_move_task(user, project_id), do: optional_parent_create(user, Project, project_id)

  defp require_parent_create(%{is_admin: true}, _schema, _id), do: :ok
  defp require_parent_create(_user, _schema, nil), do: {:error, :forbidden}
  defp require_parent_create(user, schema, id), do: parent_create(user, schema, id)

  defp optional_parent_create(%{is_admin: true}, _schema, _id), do: :ok
  defp optional_parent_create(_user, _schema, nil), do: :ok
  defp optional_parent_create(_user, _schema, :unchanged), do: :ok
  defp optional_parent_create(user, schema, id), do: parent_create(user, schema, id)

  defp parent_create(user, schema, id) do
    case Repo.get(schema, id) do
      nil -> {:error, :forbidden}
      parent -> authorize(user, :create, parent)
    end
  end

  @doc """
  Authorizes `action` on an execution by cascading through its owning task.
  A deleted/absent task yields a nil resource, which only global admins may access.
  """
  def authorize_execution(user, action, %TaskExecution{} = execution) do
    task =
      case execution.task_definition_id && Repo.get(TaskDefinition, execution.task_definition_id) do
        %TaskDefinition{} = t -> t
        _ -> nil
      end

    authorize(user, action, task)
  end

  @doc "Boolean map of what `user` can do on `resource` — used by serializers/UI."
  def can_map(user, resource), do: can_from_level(effective_level(user, resource))

  def can_from_level(level) do
    %{
      view:          level >= @required_level.view,
      run:           level >= @required_level.run,
      create:        level >= @required_level.create,
      edit:          level >= @required_level.edit,
      delete:        level >= @required_level.delete,
      manageMembers: level >= @required_level.manage_members,
      manageSecrets: level >= @required_level.manage_secrets
    }
  end

  def level_name(n), do: Map.get(@level_names, n, "None")

  @doc "All access levels (value/name/description) — single source for the picker UI."
  def levels, do: @levels

  # ── Effective level for a single resource ─────────────────────────────────────
  #
  # Loads the user's memberships and the group parent map once, then walks the
  # ancestry purely via `group_chain/3` — the same traversal `scope/1` uses — so
  # there is no query per ancestor level.

  def effective_level(%{is_admin: true}, _resource), do: 50
  def effective_level(nil, _resource), do: 0
  def effective_level(%{id: uid}, resource), do: effective_level(uid, resource)

  def effective_level(uid, %Group{} = group) when is_integer(uid),
    do: level_for(group, direct_levels(uid), group_parents())

  def effective_level(uid, %Project{} = project) when is_integer(uid),
    do: level_for(project, direct_levels(uid), group_parents())

  def effective_level(uid, %TaskDefinition{} = task) when is_integer(uid),
    do: level_for(task, direct_levels(uid), group_parents())

  def effective_level(_uid, _resource), do: 0

  defp level_for(%Group{id: id}, direct, parent_of),
    do: group_chain(id, direct["group"], parent_of)

  defp level_for(%Project{id: id, group_id: gid}, direct, parent_of),
    do: max(Map.get(direct["project"], id, 0), group_chain(gid, direct["group"], parent_of))

  defp level_for(%TaskDefinition{id: id, project_id: pid}, direct, parent_of) do
    project_level =
      case pid && Repo.get(Project, pid) do
        %Project{} = p -> level_for(p, direct, parent_of)
        _ -> 0
      end

    max(Map.get(direct["task"], id, 0), project_level)
  end

  # User's direct memberships as %{"group" => %{id => level}, "project" => ..., "task" => ...}.
  # Shared by effective_level/2 and scope/1.
  defp direct_levels(uid) do
    Repo.all(from m in Membership, where: m.user_id == ^uid,
      select: {m.subject_type, m.subject_id, m.access_level})
    |> Enum.reduce(%{"group" => %{}, "project" => %{}, "task" => %{}},
      fn {type, id, lvl}, acc ->
        update_in(acc[type], &Map.update(&1, id, lvl, fn cur -> max(cur, lvl) end))
      end)
  end

  defp group_parents do
    Repo.all(from g in Group, select: {g.id, g.parent_id}) |> Map.new()
  end

  # ── Visibility scope (single pass, in-memory) ─────────────────────────────────

  @doc """
  Returns the set of resources a user may see, each mapped to their effective
  level:

      %{groups: %{id => level}, projects: %{id => level}, tasks: %{id => level}}

  A key being present means "visible" (listable). Ancestor groups/projects are
  included with their own (possibly 0) level purely so the navigation tree can
  render a path to an accessible child.
  """
  def scope(%{is_admin: true}) do
    %{
      groups:   Repo.all(from g in Group, select: g.id)            |> Map.new(&{&1, 50}),
      projects: Repo.all(from p in Project, select: p.id)          |> Map.new(&{&1, 50}),
      tasks:    Repo.all(from t in TaskDefinition, select: t.id)   |> Map.new(&{&1, 50})
    }
  end

  def scope(nil), do: %{groups: %{}, projects: %{}, tasks: %{}}

  def scope(%{id: uid}) do
    groups   = Repo.all(from g in Group, select: {g.id, g.parent_id})
    projects = Repo.all(from p in Project, select: {p.id, p.group_id})
    tasks    = Repo.all(from t in TaskDefinition, select: {t.id, t.project_id})

    parent_of        = Map.new(groups)
    group_of_project = Map.new(projects)
    project_of_task  = Map.new(tasks)

    direct = direct_levels(uid)

    gchain = fn gid -> group_chain(gid, direct["group"], parent_of) end

    plevel = fn pid ->
      gid = Map.get(group_of_project, pid)
      max(Map.get(direct["project"], pid, 0), gchain.(gid))
    end

    levels_group   = Map.new(groups,   fn {gid, _} -> {gid, gchain.(gid)} end)
    levels_project = Map.new(projects, fn {pid, _} -> {pid, plevel.(pid)} end)

    levels_task =
      Map.new(tasks, fn {tid, pid} ->
        plvl = if pid, do: plevel.(pid), else: 0
        {tid, max(Map.get(direct["task"], tid, 0), plvl)}
      end)

    full_groups   = for {id, l} <- levels_group,   l > 0, into: MapSet.new(), do: id
    full_projects = for {id, l} <- levels_project, l > 0, into: MapSet.new(), do: id
    full_tasks    = for {id, l} <- levels_task,    l > 0, into: MapSet.new(), do: id

    # Ancestor groups/projects needed only to render a path to a visible child.
    nav_groups =
      (Enum.flat_map(full_groups, fn gid -> ancestors(Map.get(parent_of, gid), parent_of) end) ++
       Enum.flat_map(full_projects, fn pid -> ancestors(Map.get(group_of_project, pid), parent_of) end) ++
       Enum.flat_map(full_tasks, fn tid ->
         case Map.get(project_of_task, tid) do
           nil -> []
           pid -> ancestors(Map.get(group_of_project, pid), parent_of)
         end
       end))
      |> MapSet.new()

    nav_projects =
      full_tasks
      |> Enum.flat_map(fn tid -> List.wrap(Map.get(project_of_task, tid)) end)
      |> MapSet.new()

    vis_groups   = MapSet.union(full_groups, nav_groups)
    vis_projects = MapSet.union(full_projects, nav_projects)

    %{
      groups:   Map.take(levels_group,   MapSet.to_list(vis_groups)),
      projects: Map.take(levels_project, MapSet.to_list(vis_projects)),
      tasks:    Map.take(levels_task,    MapSet.to_list(full_tasks))
    }
  end

  # In-memory chain max over the group ancestry.
  defp group_chain(nil, _direct_groups, _parent_of), do: 0
  defp group_chain(gid, direct_groups, parent_of) do
    own = Map.get(direct_groups, gid, 0)
    max(own, group_chain(Map.get(parent_of, gid), direct_groups, parent_of))
  end

  # List of [gid, parent, grandparent, ...] starting at gid; [] for nil.
  defp ancestors(nil, _parent_of), do: []
  defp ancestors(gid, parent_of), do: [gid | ancestors(Map.get(parent_of, gid), parent_of)]
end
