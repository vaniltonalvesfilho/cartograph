defmodule CartographBackend.Agents.AnthropicCredential do
  use Ecto.Schema
  import Ecto.Changeset

  alias CartographBackend.{Ids, Vault}

  # An Anthropic API key registered on a project. `code` is the public id the
  # DSL references (`step "agent" { secret "anthropic-uI0IOQ45" }`), generated
  # once like job codes. The key is the secret: stored encrypted, never
  # returned by the API after saving.
  schema "anthropic_credentials" do
    field :name, :string
    field :code, :string
    field :api_key_encrypted, :binary, redact: true
    field :api_key, :string, virtual: true, redact: true
    field :project_id, :integer

    timestamps()
  end

  # Anthropic keys are `sk-ant-...`; this catches pasted garbage early, the
  # way the Slack URL regex does.
  @api_key_format ~r/^sk-ant-\S+$/

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:name, :api_key, :project_id])
    |> validate_required([:name, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> require_api_key_on_insert()
    |> validate_format(:api_key, @api_key_format,
      message: "must be an Anthropic API key (sk-ant-...)"
    )
    |> put_new_code()
    |> unique_constraint(:code)
    |> unique_constraint([:project_id, :name], message: "already used in this project")
    |> encrypt_api_key()
  end

  # The key is mandatory when creating; on update a blank value means
  # "keep the stored one" (the API never echoes it back to be re-submitted).
  defp require_api_key_on_insert(%{data: %{id: nil}} = cs), do: validate_required(cs, [:api_key])
  defp require_api_key_on_insert(cs), do: cs

  # Public code `"anthropic-<suffix>"`, same shape and generator as job codes;
  # derived only on insert of a valid changeset, never overwritten.
  defp put_new_code(%{valid?: true, data: %{id: nil, code: nil}} = cs),
    do: put_change(cs, :code, Ids.generate_job_code(__MODULE__, "anthropic"))

  defp put_new_code(cs), do: cs

  defp encrypt_api_key(cs) do
    case get_change(cs, :api_key) do
      nil -> cs
      "" -> cs
      api_key -> put_change(cs, :api_key_encrypted, Vault.encrypt(api_key))
    end
  end
end
