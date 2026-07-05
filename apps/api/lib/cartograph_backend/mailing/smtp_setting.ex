defmodule CartographBackend.Mailing.SmtpSetting do
  use Ecto.Schema
  import Ecto.Changeset
  alias CartographBackend.Vault

  # Singleton row: the application keeps at most one SMTP configuration.
  schema "smtp_settings" do
    field :host,               :string
    field :port,               :integer, default: 587
    field :username,           :string
    field :password_encrypted, :binary, redact: true
    field :password,           :string, virtual: true, redact: true
    field :from_name,          :string
    field :from_email,         :string
    field :tls,                :string, default: "if_available"
    field :auth,               :boolean, default: true
    field :enabled,            :boolean, default: false

    timestamps()
  end

  # TLS negotiation mode for the SMTP connection.
  @tls_modes ~w(always if_available never)

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:host, :port, :username, :password, :from_name, :from_email, :tls, :auth, :enabled])
    |> validate_required([:host, :port, :from_email])
    |> validate_number(:port, greater_than: 0, less_than_or_equal_to: 65_535)
    |> validate_inclusion(:tls, @tls_modes, message: "must be one of: always, if_available, never")
    # Guard against SMTP header injection: a from_email containing CR/LF or
    # angle brackets could smuggle extra headers into the message.
    |> validate_format(:from_email, ~r/^[^\s<>\r\n]+@[^\s<>\r\n]+$/, message: "invalid email address")
    |> validate_no_crlf(:from_name)
    |> encrypt_password()
  end

  defp validate_no_crlf(cs, field) do
    validate_change(cs, field, fn ^field, value ->
      if is_binary(value) and String.match?(value, ~r/[\r\n]/),
        do: [{field, "must not contain line breaks"}],
        else: []
    end)
  end

  defp encrypt_password(cs) do
    case get_change(cs, :password) do
      nil -> cs
      ""  -> cs
      pw  -> put_change(cs, :password_encrypted, Vault.encrypt(pw))
    end
  end
end
