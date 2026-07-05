defmodule CartographBackendWeb.Graphql.Resolvers.Groups do
  alias CartographBackend.{Groups, Accounts}
  alias CartographBackendWeb.Graphql.Authz

  def list(_parent, _args, res) do
    levels = Authz.scope(res).groups

    groups =
      Groups.list_groups()
      |> Enum.filter(&Map.has_key?(levels, &1.id))

    {:ok, groups}
  end

  def get(_parent, %{id: id}, res) do
    with {:ok, group} <- Groups.get_group(Authz.to_id(id)),
         :ok <- Authz.authorize(res, :view, group) do
      {:ok, group}
    end
  end

  def create(_parent, args, res) do
    user = Authz.current_user(res)
    parent_id = Authz.to_id(args[:parent_id])

    with :ok <- Authz.authorize_create_group(res, parent_id),
         {:ok, group} <- Groups.create_group(%{"name" => args.name, "parent_id" => parent_id}) do
      Accounts.grant_owner(user, "group", group.id)
      {:ok, group}
    end
  end

  def update(_parent, %{id: id} = args, res) do
    attrs = args |> Map.drop([:id, :parent_id]) |> atom_to_string_keys()
    attrs = maybe_put_parent(attrs, args)

    with {:ok, group} <- Groups.get_group(Authz.to_id(id)),
         :ok <- Authz.authorize(res, :edit, group),
         {:ok, group} <- Groups.update_group(group.id, attrs) do
      {:ok, group}
    else
      {:error, :cycle_detected} -> {:error, "Ciclo de hierarquia detectado"}
      other -> other
    end
  end

  def delete(_parent, %{id: id}, res) do
    with {:ok, group} <- Groups.get_group(Authz.to_id(id)),
         :ok <- Authz.authorize(res, :delete, group),
         {:ok, _} <- Groups.delete_group(group.id) do
      {:ok, true}
    end
  end

  defp maybe_put_parent(attrs, args) do
    if Map.has_key?(args, :parent_id),
      do: Map.put(attrs, "parent_id", Authz.to_id(args[:parent_id])),
      else: attrs
  end

  defp atom_to_string_keys(map) do
    Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)
  end
end
