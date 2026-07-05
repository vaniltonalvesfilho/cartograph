defmodule CartographBackendWeb.MemberController do
  use CartographBackendWeb, :controller

  alias CartographBackend.{Accounts, Authorization, Groups, Tasks}
  alias CartographBackendWeb.Serializers

  # ── Reference data ────────────────────────────────────────────────────────────

  # The access levels available to the member picker (single source: Authorization).
  def levels(conn, _params), do: json(conn, Authorization.levels())

  # ── Groups ────────────────────────────────────────────────────────────────────

  def index_group(conn, %{"group_id" => id}) do
    with_resource(conn, &Groups.get_group/1, id, :view, fn group ->
      members = Accounts.list_memberships("group", group.id)
      json(conn, member_payload(conn, members, group))
    end)
  end

  def create_group(conn, %{"group_id" => gid} = params) do
    with_resource(conn, &Groups.get_group/1, gid, :manage_members, fn group ->
      do_add(conn, "group", group, params)
    end)
  end

  def delete_group(conn, %{"group_id" => gid, "user_id" => uid}) do
    with_resource(conn, &Groups.get_group/1, gid, :manage_members, fn group ->
      do_remove(conn, "group", group.id, uid)
    end)
  end

  # ── Projects ──────────────────────────────────────────────────────────────────

  def index_project(conn, %{"project_id" => id}) do
    with_resource(conn, &Groups.get_project/1, id, :view, fn project ->
      members = Accounts.list_memberships("project", project.id)
      json(conn, member_payload(conn, members, project))
    end)
  end

  def create_project(conn, %{"project_id" => pid} = params) do
    with_resource(conn, &Groups.get_project/1, pid, :manage_members, fn project ->
      do_add(conn, "project", project, params)
    end)
  end

  def delete_project(conn, %{"project_id" => pid, "user_id" => uid}) do
    with_resource(conn, &Groups.get_project/1, pid, :manage_members, fn project ->
      do_remove(conn, "project", project.id, uid)
    end)
  end

  # ── Tasks ─────────────────────────────────────────────────────────────────────

  def index_task(conn, %{"task_id" => id}) do
    with_resource(conn, &Tasks.get_task/1, id, :view, fn task ->
      members = Accounts.list_memberships("task", task.id)
      json(conn, member_payload(conn, members, task))
    end)
  end

  def create_task(conn, %{"task_id" => tid} = params) do
    with_resource(conn, &Tasks.get_task/1, tid, :manage_members, fn task ->
      do_add(conn, "task", task, params)
    end)
  end

  def delete_task(conn, %{"task_id" => tid, "user_id" => uid}) do
    with_resource(conn, &Tasks.get_task/1, tid, :manage_members, fn task ->
      do_remove(conn, "task", task.id, uid)
    end)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  # Loads the subject, authorizes the action, then runs `fun` with the resource.
  defp with_resource(conn, getter, id, action, fun) do
    with int_id when is_integer(int_id) <- to_int(id),
         {:ok, resource} <- getter.(int_id),
         true <- Authorization.can?(conn.assigns.current_user, action, resource) do
      fun.(resource)
    else
      nil -> conn |> put_status(400) |> json(%{error: "Bad request"})
      false -> conn |> put_status(403) |> json(%{error: "Forbidden"})
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  # Members + the requesting user's own effective level, so the UI can decide
  # whether to show member-management controls without a separate round-trip.
  defp member_payload(conn, members, resource) do
    %{
      members: Enum.map(members, &Serializers.membership/1),
      myLevel: Authorization.effective_level(conn.assigns.current_user, resource)
    }
  end

  defp do_add(conn, type, resource, params) do
    uid   = to_int(params["userId"])
    level = params["accessLevel"]
    granter_level = Authorization.effective_level(conn.assigns.current_user, resource)

    cond do
      not is_integer(level) ->
        conn |> put_status(400) |> json(%{error: "accessLevel is required"})

      # Prevent privilege escalation: you cannot grant a level above your own
      # effective level on this resource (admins have 50, so are unaffected).
      level > granter_level ->
        conn |> put_status(403) |> json(%{error: "You cannot grant a level above your own"})

      true ->
        case Accounts.add_member(uid, type, resource.id, level) do
          {:ok, m} ->
            m = CartographBackend.Repo.preload(m, :user)
            conn |> put_status(201) |> json(Serializers.membership(m))
          {:error, cs} ->
            unprocessable(conn, cs)
        end
    end
  end

  defp do_remove(conn, type, subject_id, user_id) do
    case to_int(user_id) do
      nil ->
        conn |> put_status(400) |> json(%{error: "Bad request"})

      uid ->
        case Accounts.remove_member(uid, type, subject_id) do
          {:ok, _}             -> send_resp(conn, 204, "")
          {:error, :not_found} -> send_resp(conn, 404, "")
        end
    end
  end

  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp to_int(_), do: nil
end
