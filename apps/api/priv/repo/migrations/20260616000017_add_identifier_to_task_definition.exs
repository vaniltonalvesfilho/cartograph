defmodule CartographBackend.Repo.Migrations.AddIdentifierToTaskDefinition do
  use Ecto.Migration

  import Ecto.Query

  alias CartographBackend.Repo

  # Adds a user-provided, immutable `identifier` (slug) to jobs and switches the
  # job `code` to the public global-id format `<identifier>-<8-char suffix>`
  # (e.g. `backup-uI0IOQ45`). Groups/projects keep their numeric `code`.
  #
  #   1. add nullable `identifier` to task_definition
  #   2. backfill: identifier := slug(name); code := "<identifier>-<suffix>"
  #
  # `identifier` stays nullable here (additive deploy); the changeset requires it
  # on every insert from now on. `code` already carries a unique index.
  @alphabet ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

  def up do
    alter table(:task_definition) do
      add :identifier, :string
    end

    flush()

    backfill()
  end

  def down do
    # Restore numeric codes so a re-run of 0016's format is consistent, then drop.
    alter table(:task_definition) do
      remove :identifier
    end
  end

  # ── Backfill ────────────────────────────────────────────────────────────────

  defp backfill do
    rows = from(t in "task_definition", select: {t.id, t.name}) |> Repo.all()

    Enum.reduce(rows, MapSet.new(), fn {id, name}, used ->
      identifier = slug(name)
      code = unique_code(identifier, used)

      from(t in "task_definition", where: t.id == ^id)
      |> Repo.update_all(set: [identifier: identifier, code: code])

      MapSet.put(used, code)
    end)
  end

  # Lowercase, collapse non-alphanumeric runs into single hyphens, trim. Falls
  # back to "job" when the name has no usable characters.
  defp slug(name) do
    slug =
      (name || "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    if slug == "", do: "job", else: slug
  end

  defp unique_code(identifier, used) do
    code = "#{identifier}-#{suffix()}"

    if MapSet.member?(used, code) or exists?(code) do
      unique_code(identifier, used)
    else
      code
    end
  end

  defp exists?(code) do
    Repo.exists?(from(t in "task_definition", where: t.code == ^code))
  end

  defp suffix do
    for _ <- 1..8, into: "", do: <<Enum.random(@alphabet)>>
  end
end
