defmodule CartographBackend.Ids do
  @moduledoc """
  Generates the public, copy-friendly `code` carried by groups, projects and
  tasks.

  Two formats coexist:

    * **Groups / projects** — `code` is **8 decimal digits** (leading zeros
      allowed, kept as a string), unique per table. See `generate_code/1`.

    * **Jobs** — `code` is the global id `"<identifier>-<suffix>"` where the
      suffix is 8 base62 chars (e.g. `backup-uI0IOQ45`). The `identifier` is the
      user-provided slug; the suffix makes it unique. This is the canonical
      reference used by the DSL `use "<code>"` form. See `generate_job_code/2`.

  Codes are generated at random and checked for collision against the target
  table, so they are non-sequential and not trivially enumerable.
  """

  import Ecto.Query

  alias CartographBackend.Repo

  @code_len 8
  @suffix_len 8
  @max_attempts 50

  # base62 alphabet for job-code suffixes (mixed case + digits).
  @alphabet ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

  @doc """
  Returns a fresh 8-digit code that does not yet exist in `queryable`.

  `queryable` is any Ecto schema/queryable carrying a `code` column, e.g.
  `CartographBackend.Groups.Group`. Retries on the (rare) collision.
  """
  @spec generate_code(Ecto.Queryable.t()) :: String.t()
  def generate_code(queryable), do: generate_code(queryable, 0)

  defp generate_code(_queryable, attempts) when attempts >= @max_attempts do
    # 8 digits = 1e8 space; exhausting 50 random draws means the table is
    # implausibly full. Surface loudly rather than risk a duplicate insert.
    raise "CartographBackend.Ids: could not generate a unique code after #{@max_attempts} attempts"
  end

  defp generate_code(queryable, attempts) do
    code = random_code()

    if exists?(queryable, code) do
      generate_code(queryable, attempts + 1)
    else
      code
    end
  end

  @doc "A random 8-digit code string (no uniqueness check)."
  @spec random_code() :: String.t()
  def random_code do
    (:rand.uniform(100_000_000) - 1)
    |> Integer.to_string()
    |> String.pad_leading(@code_len, "0")
  end

  @doc """
  Returns a fresh job code `"<identifier>-<suffix>"` not yet present in
  `queryable` (a schema carrying a `code` column, e.g. `TaskDefinition`).

  The `identifier` is taken verbatim; only the trailing base62 suffix is random,
  so two jobs sharing an identifier get distinct codes. Retries on collision.
  """
  @spec generate_job_code(Ecto.Queryable.t(), String.t()) :: String.t()
  def generate_job_code(queryable, identifier), do: generate_job_code(queryable, identifier, 0)

  defp generate_job_code(_queryable, _identifier, attempts) when attempts >= @max_attempts do
    raise "CartographBackend.Ids: could not generate a unique job code after #{@max_attempts} attempts"
  end

  defp generate_job_code(queryable, identifier, attempts) do
    code = "#{identifier}-#{random_suffix()}"

    if exists?(queryable, code) do
      generate_job_code(queryable, identifier, attempts + 1)
    else
      code
    end
  end

  @doc "A random 8-char base62 suffix (no uniqueness check)."
  @spec random_suffix() :: String.t()
  def random_suffix do
    for _ <- 1..@suffix_len, into: "", do: <<Enum.random(@alphabet)>>
  end

  defp exists?(queryable, code) do
    Repo.exists?(from q in queryable, where: q.code == ^code)
  end
end
