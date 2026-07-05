defmodule CartographBackend.Repo.Migrations.AddCodeToGroupsProjectsTasks do
  use Ecto.Migration

  import Ecto.Query

  alias CartographBackend.Repo

  @tables ~w(groups projects task_definition)a

  # Additive migration:
  #   1. add nullable `code` (string) to groups / projects / task_definition
  #   2. backfill every existing row with a unique 8-digit numeric code
  #   3. add a unique index on `code` per table
  #
  # `code` stays nullable here (no `null: false`) so the deploy is additive and
  # backward compatible; changesets set `code` on every insert from now on, and a
  # later migration can tighten to `null: false` once all environments are
  # backfilled.
  def up do
    for table <- @tables do
      alter table(table) do
        add :code, :string
      end
    end

    flush()

    for table <- @tables, do: backfill(table)

    create unique_index(:groups, [:code])
    create unique_index(:projects, [:code])
    create unique_index(:task_definition, [:code])
  end

  def down do
    drop unique_index(:task_definition, [:code])
    drop unique_index(:projects, [:code])
    drop unique_index(:groups, [:code])

    for table <- @tables do
      alter table(table) do
        remove :code
      end
    end
  end

  # ── Backfill ────────────────────────────────────────────────────────────────

  defp backfill(table) do
    ids =
      from(t in table_name(table), select: t.id) |> Repo.all()

    # Track codes generated within this run so two rows in the same table can't
    # collide before the unique index exists.
    Enum.reduce(ids, MapSet.new(), fn id, used ->
      code = unique_code(table, used)

      from(t in table_name(table), where: t.id == ^id)
      |> Repo.update_all(set: [code: code])

      MapSet.put(used, code)
    end)
  end

  defp unique_code(table, used) do
    code = gen_code()

    if MapSet.member?(used, code) or exists?(table, code) do
      unique_code(table, used)
    else
      code
    end
  end

  defp exists?(table, code) do
    Repo.exists?(from t in table_name(table), where: t.code == ^code)
  end

  # 8 random decimal digits, leading zeros allowed (kept as a string).
  defp gen_code do
    :rand.uniform(100_000_000) - 1
    |> Integer.to_string()
    |> String.pad_leading(8, "0")
  end

  defp table_name(:groups), do: "groups"
  defp table_name(:projects), do: "projects"
  defp table_name(:task_definition), do: "task_definition"
end
