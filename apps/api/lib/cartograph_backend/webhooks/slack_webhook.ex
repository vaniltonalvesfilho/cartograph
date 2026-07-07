defmodule CartographBackend.Webhooks.SlackWebhook do
  use Ecto.Schema
  import Ecto.Changeset

  alias CartographBackend.{Ids, Vault}

  # A Slack incoming webhook registered on a project. `code` is the public id
  # the DSL references (`step "notify" { secret "slack-uI0IOQ45" }`), generated
  # once like job codes. The URL is the secret: stored encrypted, never
  # returned by the API after saving.
  schema "slack_webhooks" do
    field :name, :string
    field :code, :string
    field :url_encrypted, :binary, redact: true
    field :url, :string, virtual: true, redact: true
    field :project_id, :integer

    timestamps()
  end

  # Only genuine Slack incoming-webhook URLs are accepted: the server POSTs to
  # this URL at job runtime, so a free-form URL would be an SSRF vector.
  @url_format ~r{^https://hooks\.slack\.com/\S+$}

  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:name, :url, :project_id])
    |> validate_required([:name, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> require_url_on_insert()
    |> validate_format(:url, @url_format,
      message: "must be a Slack incoming webhook URL (https://hooks.slack.com/...)"
    )
    |> put_new_code()
    |> unique_constraint(:code)
    |> unique_constraint([:project_id, :name], message: "already used in this project")
    |> encrypt_url()
  end

  # The URL is mandatory when creating; on update a blank value means
  # "keep the stored one" (the API never echoes it back to be re-submitted).
  defp require_url_on_insert(%{data: %{id: nil}} = cs), do: validate_required(cs, [:url])
  defp require_url_on_insert(cs), do: cs

  # Public code `"slack-<suffix>"`, same shape and generator as job codes;
  # derived only on insert of a valid changeset, never overwritten.
  defp put_new_code(%{valid?: true, data: %{id: nil, code: nil}} = cs),
    do: put_change(cs, :code, Ids.generate_job_code(__MODULE__, "slack"))

  defp put_new_code(cs), do: cs

  defp encrypt_url(cs) do
    case get_change(cs, :url) do
      nil -> cs
      "" -> cs
      url -> put_change(cs, :url_encrypted, Vault.encrypt(url))
    end
  end
end
