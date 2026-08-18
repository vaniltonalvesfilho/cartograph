defmodule CartographBackend.Accounts do
  import Ecto.Query
  alias CartographBackend.Repo
  alias CartographBackend.Accounts.{User, Membership, ApiToken}
  alias CartographBackend.Groups.Project

  # ── Auth ──────────────────────────────────────────────────────────────────────

  def authenticate(email, password) do
    user = Repo.get_by(User, email: email)

    cond do
      user && Bcrypt.verify_pass(password, user.password_hash) && user.totp_enabled ->
        {:ok, :totp_required, user}

      user && Bcrypt.verify_pass(password, user.password_hash) ->
        {:ok, user}

      user ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      true ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  # ── TOTP ──────────────────────────────────────────────────────────────────────

  def generate_totp_secret, do: NimbleTOTP.secret()

  def totp_provisioning_uri(user, secret) do
    NimbleTOTP.otpauth_uri("Cartograph:#{user.email}", secret, issuer: "Cartograph")
  end

  def save_totp_secret(user, secret) do
    user |> User.totp_changeset(%{totp_secret: secret, totp_enabled: false}) |> Repo.update()
  end

  def enable_totp(user, code) do
    if valid_totp?(user, code) do
      user
      |> User.totp_changeset(%{totp_enabled: true, totp_last_used_at: DateTime.utc_now()})
      |> Repo.update()
    else
      {:error, :invalid_code}
    end
  end

  def disable_totp(user) do
    user
    |> User.totp_changeset(%{totp_secret: nil, totp_enabled: false, totp_last_used_at: nil})
    |> Repo.update()
  end

  @doc """
  Checks a TOTP code and burns it.

  A code stays valid for its whole 30-second step, so without recording the
  step that was accepted, a code observed over the user's shoulder (or replayed
  from a proxied request) works a second time. `:since` makes NimbleTOTP reject
  any code from a step at or before the last accepted one.
  """
  def verify_totp(user, code) do
    if valid_totp?(user, code) do
      case user
           |> User.totp_changeset(%{totp_last_used_at: DateTime.utc_now()})
           |> Repo.update() do
        {:ok, _} -> :ok
        {:error, _} -> {:error, :invalid_code}
      end
    else
      {:error, :invalid_code}
    end
  end

  defp valid_totp?(%{totp_secret: nil}, _code), do: false

  defp valid_totp?(user, code) when is_binary(code) do
    NimbleTOTP.valid?(user.totp_secret, code, since: user.totp_last_used_at)
  end

  defp valid_totp?(_user, _code), do: false

  @doc "Confirms a user's own password, for re-authenticating a sensitive action."
  def verify_password(user, password) when is_binary(password) do
    if Bcrypt.verify_pass(password, user.password_hash) do
      :ok
    else
      {:error, :invalid_credentials}
    end
  end

  def verify_password(_user, _password) do
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  # ── Users ─────────────────────────────────────────────────────────────────────

  def list_users, do: Repo.all(from u in User, order_by: u.name)

  @doc """
  Whether the user has any business seeing the user directory.

  The picker exists so that someone who can add members can find them, so the
  directory is limited to the people who can actually do that: a global admin,
  or anyone holding `manage_members` somewhere. Otherwise the lowest-level
  account on the instance could pull every registered name and email, which is
  a phishing list.
  """
  def may_list_pickable_users?(%{is_admin: true}), do: true

  def may_list_pickable_users?(%{id: user_id}) when not is_nil(user_id) do
    level = CartographBackend.Authorization.required_level(:manage_members)

    Repo.exists?(from m in Membership, where: m.user_id == ^user_id and m.access_level >= ^level)
  end

  def may_list_pickable_users?(_), do: false

  @doc "Minimal list for member pickers — see `may_list_pickable_users?/1`."
  def pickable_users do
    Repo.all(from u in User, order_by: u.name, select: %{id: u.id, name: u.name, email: u.email})
  end

  def count_admins, do: Repo.aggregate(from(u in User, where: u.is_admin == true), :count)

  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      u -> {:ok, u}
    end
  end

  def create_user(attrs) do
    %User{} |> User.changeset(attrs) |> Repo.insert()
  end

  def update_user(id, attrs) do
    with {:ok, user} <- get_user(id) do
      user |> User.update_changeset(attrs) |> Repo.update()
    end
  end

  @doc """
  Privileged variant that also applies the `is_admin` flag from `attrs`.
  Callers must have verified the acting user is a global admin.
  """
  def admin_create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> User.admin_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Privileged variant of `update_user/2` — see `admin_create_user/1`."
  def admin_update_user(id, attrs) do
    with {:ok, user} <- get_user(id) do
      user
      |> User.update_changeset(attrs)
      |> User.admin_changeset(attrs)
      |> Repo.update()
    end
  end

  def delete_user(id) do
    with {:ok, user} <- get_user(id), do: Repo.delete(user)
  end

  # ── Memberships ───────────────────────────────────────────────────────────────

  def list_memberships(subject_type, subject_id) do
    Repo.all(
      from m in Membership,
        where: m.subject_type == ^subject_type and m.subject_id == ^subject_id,
        preload: :user,
        order_by: [desc: m.access_level]
    )
  end

  @doc """
  Distinct email addresses of every user who is a member of the given project
  or of the group that contains it. Used to notify stakeholders of a job's
  execution failure. Returns `[]` when the project is unknown.
  """
  def project_and_group_member_emails(project_id) do
    group_id = Repo.one(from p in Project, where: p.id == ^project_id, select: p.group_id)

    base =
      from m in Membership,
        join: u in User,
        on: u.id == m.user_id,
        where: m.subject_type == "project" and m.subject_id == ^project_id,
        select: u.email

    query =
      if group_id do
        from [m, _u] in base,
          or_where: m.subject_type == "group" and m.subject_id == ^group_id
      else
        base
      end

    query |> distinct(true) |> Repo.all()
  end

  def add_member(user_id, subject_type, subject_id, access_level) do
    %Membership{}
    |> Membership.changeset(%{
      user_id: user_id,
      subject_type: subject_type,
      subject_id: subject_id,
      access_level: access_level
    })
    |> Repo.insert(
      on_conflict: [set: [access_level: access_level]],
      conflict_target: [:user_id, :subject_type, :subject_id]
    )
  end

  @doc """
  Grants the creator Navigator (40) on a freshly created resource so they own it.
  No-op for global admins, who already have full access via `is_admin`.
  """
  def grant_owner(%{is_admin: true}, _type, _id), do: :ok

  def grant_owner(%{id: uid}, subject_type, subject_id) do
    add_member(uid, subject_type, subject_id, 40)
    :ok
  end

  def grant_owner(_user, _type, _id), do: :ok

  def remove_member(user_id, subject_type, subject_id) do
    case Repo.get_by(Membership,
           user_id: user_id,
           subject_type: subject_type,
           subject_id: subject_id
         ) do
      nil -> {:error, :not_found}
      m -> Repo.delete(m)
    end
  end

  # ── API Tokens ────────────────────────────────────────────────────────────────

  def list_api_tokens(user) do
    from(t in ApiToken,
      where: t.user_id == ^user.id,
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  def create_api_token(user, name, expires_at \\ nil) do
    raw = "cg_" <> Base.encode16(:crypto.strong_rand_bytes(24), case: :lower)
    hash = :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
    prefix = String.slice(raw, 0, 11)

    case %ApiToken{}
         |> ApiToken.changeset(%{
           name: name,
           token_hash: hash,
           prefix: prefix,
           user_id: user.id,
           expires_at: expires_at
         })
         |> Repo.insert() do
      {:ok, token} -> {:ok, token, raw}
      error -> error
    end
  end

  def revoke_api_token(user, token_id) do
    case Repo.get_by(ApiToken, id: token_id, user_id: user.id) do
      nil -> {:error, :not_found}
      token -> Repo.delete(token)
    end
  end

  def verify_api_token(raw) do
    hash = :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
    now = DateTime.utc_now()

    query =
      from t in ApiToken,
        where: t.token_hash == ^hash,
        where: is_nil(t.expires_at) or t.expires_at > ^now,
        preload: [:user]

    case Repo.one(query) do
      nil ->
        {:error, :invalid}

      token ->
        Repo.update!(Ecto.Changeset.change(token, last_used_at: DateTime.truncate(now, :second)))
        {:ok, token.user}
    end
  end
end
