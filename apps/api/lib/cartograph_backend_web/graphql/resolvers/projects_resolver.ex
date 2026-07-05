defmodule CartographBackendWeb.Graphql.Resolvers.Projects do
  alias CartographBackend.{Groups, Accounts}
  alias CartographBackendWeb.Graphql.Authz

  def list(_parent, args, res) do
    levels = Authz.scope(res).projects
    opts = if gid = Authz.to_id(args[:group_id]), do: [group_id: gid], else: []

    projects =
      Groups.list_projects(opts)
      |> Enum.filter(&Map.has_key?(levels, &1.id))

    {:ok, projects}
  end

  def get(_parent, %{id: id}, res) do
    with {:ok, project} <- Groups.get_project(Authz.to_id(id)),
         :ok <- Authz.authorize(res, :view, project) do
      {:ok, project}
    end
  end

  def create(_parent, args, res) do
    user = Authz.current_user(res)
    group_id = Authz.to_id(args[:group_id])

    with :ok <- Authz.authorize_create_project(res, group_id),
         {:ok, project} <- Groups.create_project(%{"name" => args.name, "group_id" => group_id}) do
      Accounts.grant_owner(user, "project", project.id)
      {:ok, project}
    end
  end

  def update(_parent, %{id: id} = args, res) do
    attrs = args |> Map.drop([:id, :group_id]) |> atom_to_string_keys()
    attrs = maybe_put_group(attrs, args)

    with {:ok, project} <- Groups.get_project(Authz.to_id(id)),
         :ok <- Authz.authorize(res, :edit, project),
         :ok <- Authz.authorize_move_project(res, Map.get(attrs, "group_id", :unchanged)),
         {:ok, project} <- Groups.update_project(project.id, attrs) do
      {:ok, project}
    end
  end

  def delete(_parent, %{id: id}, res) do
    with {:ok, project} <- Groups.get_project(Authz.to_id(id)),
         :ok <- Authz.authorize(res, :delete, project),
         {:ok, _} <- Groups.delete_project(project.id) do
      {:ok, true}
    end
  end

  defp maybe_put_group(attrs, args) do
    if Map.has_key?(args, :group_id),
      do: Map.put(attrs, "group_id", Authz.to_id(args[:group_id])),
      else: attrs
  end

  defp atom_to_string_keys(map) do
    Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)
  end
end
