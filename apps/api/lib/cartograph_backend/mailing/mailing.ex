defmodule CartographBackend.Mailing do
  @moduledoc """
  Outbound email context. Holds the singleton SMTP relay configuration
  (configurable from the admin dashboard) and delivers transactional emails.

  The SMTP password is stored encrypted (via `CartographBackend.Vault`) and the
  relay config is assembled at runtime, so credentials never live in compile
  config and are decrypted only at the moment of sending.
  """

  import Ecto.Query
  require Logger

  alias CartographBackend.Repo
  alias CartographBackend.Vault
  alias CartographBackend.Accounts
  alias CartographBackend.Mailing.{SmtpSetting, Emails}
  alias CartographBackend.Mailer

  # ── Settings CRUD (singleton) ─────────────────────────────────────────────────

  @doc "Returns the saved SMTP settings, or nil if never configured."
  def get_settings do
    Repo.one(from s in SmtpSetting, order_by: [asc: s.id], limit: 1)
  end

  @doc "Creates or updates the single SMTP settings row."
  def upsert_settings(attrs) do
    case get_settings() do
      nil -> %SmtpSetting{}
      setting -> setting
    end
    |> SmtpSetting.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "True when SMTP is configured AND enabled — the gate for any sending."
  def configured? do
    case get_settings() do
      %SmtpSetting{enabled: true, host: host} when is_binary(host) and host != "" -> true
      _ -> false
    end
  end

  # ── Delivery ──────────────────────────────────────────────────────────────────

  @doc """
  Delivers a `Swoosh.Email`, filling in the `from` address from settings and
  building the SMTP relay config at runtime. Returns `{:ok, _}` / `{:error, _}`.
  No-op (`{:error, :not_configured}`) when SMTP is disabled/unconfigured.
  """
  def deliver(%Swoosh.Email{} = email) do
    case get_settings() do
      %SmtpSetting{enabled: true} = settings ->
        email
        |> Swoosh.Email.from(from_address(settings))
        |> Mailer.deliver(smtp_config(settings))

      _ ->
        {:error, :not_configured}
    end
  end

  @doc """
  Sends a test email to `recipient`. The caller must pass the requesting admin's
  own address — the controller never lets the recipient be a free-form field,
  so the app can't be used to probe/spam arbitrary inboxes.
  """
  def send_test(recipient) when is_binary(recipient) do
    Emails.test(recipient) |> deliver()
  end

  # ── Triggers ───────────────────────────────────────────────────────────────────

  @doc "Fire-and-forget welcome email to a newly created user."
  def send_welcome_async(user) do
    deliver_async(fn -> Emails.welcome(user) |> deliver() end)
  end

  @doc """
  Notifies every member of the job's project and group that an execution failed.
  Fire-and-forget; only runs when SMTP is configured.
  """
  def notify_execution_failure_async(execution, project_id) do
    deliver_async(fn ->
      recipients = Accounts.project_and_group_member_emails(project_id)

      Enum.each(recipients, fn email ->
        Emails.execution_failure(execution, email) |> deliver()
      end)
    end)
  end

  # ── Internals ───────────────────────────────────────────────────────────────────

  # Runs `fun` in an unlinked task so a mail failure never crashes the caller
  # (a web request, an Oban job). Logs and swallows errors.
  defp deliver_async(fun) do
    if configured?() do
      Task.Supervisor.start_child(CartographBackend.TaskSupervisor, fn ->
        try do
          case fun.() do
            {:error, reason} when reason != :not_configured ->
              Logger.warning("Email delivery failed: #{inspect(reason)}")

            _ ->
              :ok
          end
        rescue
          e -> Logger.warning("Email delivery crashed: #{Exception.message(e)}")
        end
      end)
    end

    :ok
  end

  defp from_address(%SmtpSetting{from_name: nil, from_email: email}), do: email
  defp from_address(%SmtpSetting{from_name: "", from_email: email}), do: email
  defp from_address(%SmtpSetting{from_name: name, from_email: email}), do: {name, email}

  defp smtp_config(%SmtpSetting{} = s) do
    base = [
      relay: s.host,
      port: s.port,
      ssl: s.port == 465,
      tls: tls_mode(s.tls),
      auth: auth_mode(s),
      retries: 1,
      no_mx_lookups: false,
      # SECURITY: gen_smtp does NOT verify the server certificate by default,
      # which would allow a MITM to capture credentials. Force peer verification
      # against the system CA store with hostname checking.
      tls_options: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: to_charlist(s.host),
        depth: 99,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case auth_mode(s) do
      :never -> base
      _ -> base ++ [username: s.username, password: Vault.decrypt(s.password_encrypted) || ""]
    end
  end

  defp tls_mode("always"), do: :always
  defp tls_mode("never"), do: :never
  defp tls_mode(_), do: :if_available

  defp auth_mode(%SmtpSetting{auth: true, username: u}) when is_binary(u) and u != "", do: :always
  defp auth_mode(_), do: :never
end
