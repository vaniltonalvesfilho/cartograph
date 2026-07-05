defmodule CartographBackend.Steps.ValidateStep do
  @moduledoc """
  Format-validation gate in the spirit of Bean Validation: each param names a
  validator and points at a field of the shared state (dot path; a list along
  the way fans out to every element). Any value that violates its validator
  fails the step — and therefore the job — listing every violation found.

      step "validate" {
        email    "rows.email"
        cpf      "rows.cpf"
        cnpj     "supplier.cnpj"
        telefone "rows.fone"
        cep      "rows.cep"
        regex    "rows.sku"
        pattern  "^[A-Z]{3}-[0-9]+$"
      }

  Validators: `email` · `cpf` (check digits) · `cnpj` (check digits, accepts
  the alphanumeric format in force since 2026) · `telefone` (Brazilian, DDD +
  8/9 digits, optional +55) · `cep` (8 digits) · `regex` (custom `pattern`).

  A param that matches no state field is validated as a literal value, so
  `email "teste@example.com"` also works. State fields take precedence.
  """
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext

  @validators ~w(cep cnpj cpf email regex telefone)
  # Companion options, not validators themselves.
  @options ~w(pattern)

  @impl true
  def name, do: "validate"

  @impl true
  def execute(%StepContext{params: params} = ctx) do
    with {:ok, checks} <- normalize(params) do
      violations = Enum.flat_map(checks, &run_check(ctx, &1))

      if violations == [] do
        {:ok, ctx}
      else
        Enum.each(violations, &StepContext.error(ctx, "validate: #{&1}"))
        {:error, "validate: #{length(violations)} violation(s) — #{hd(violations)}"}
      end
    end
  end

  # ── Param handling ─────────────────────────────────────────────────────────────

  defp normalize(params) do
    {options, checks} = Map.split(params, @options)

    cond do
      map_size(checks) == 0 ->
        {:error, "validate: define at least one of: #{Enum.join(@validators, ", ")}"}

      Map.has_key?(options, "pattern") and not Map.has_key?(checks, "regex") ->
        {:error, "validate: 'pattern' only makes sense together with 'regex'"}

      true ->
        Enum.reduce_while(checks, {:ok, []}, fn {key, path}, {:ok, acc} ->
          case build_check(key, path, options) do
            {:ok, check} -> {:cont, {:ok, acc ++ [check]}}
            {:error, _} = err -> {:halt, err}
          end
        end)
    end
  end

  defp build_check(key, path, options) do
    cond do
      key not in @validators ->
        {:error, "validate: unknown validator '#{key}'. Available: #{Enum.join(@validators, ", ")}"}

      not is_binary(path) or String.trim(path) == "" ->
        {:error, "validate: '#{key}' needs a state field path (e.g. #{key} \"rows.#{key}\")"}

      key == "regex" ->
        build_regex_check(String.trim(path), options)

      true ->
        {:ok, {key, String.trim(path), %{}}}
    end
  end

  defp build_regex_check(path, options) do
    case Map.get(options, "pattern") do
      pattern when is_binary(pattern) and pattern != "" ->
        case Regex.compile(pattern) do
          {:ok, re} -> {:ok, {"regex", path, %{pattern: pattern, re: re}}}
          {:error, {msg, at}} -> {:error, "validate: invalid pattern (#{msg} at position #{at})"}
        end

      _ ->
        {:error, "validate: 'regex' needs a 'pattern' param (e.g. pattern \"^[A-Z]+$\")"}
    end
  end

  # ── Checking ───────────────────────────────────────────────────────────────────

  defp run_check(ctx, {validator, path, opts}) do
    values = resolve(ctx.state, String.split(path, "."))

    if Enum.all?(values, &is_nil/1) do
      check_literal(ctx, validator, path, opts)
    else
      violations =
        Enum.flat_map(values, fn
          nil -> ["#{validator} '#{path}': field is missing"]
          value -> if valid?(validator, value, opts), do: [], else: [violation(validator, path, value, opts)]
        end)

      if violations == [] do
        StepContext.info(ctx, "validate: #{validator} '#{path}' → #{length(values)} value(s) OK")
      end

      violations
    end
  end

  # The param matched nothing in the state: validate it as a literal value, so
  # `email "teste@example.com"` works without a state lookup. On failure the
  # message covers both readings — bad literal or a mistyped field path.
  defp check_literal(ctx, validator, literal, opts) do
    if valid?(validator, literal, opts) do
      StepContext.info(ctx, "validate: #{validator} literal #{inspect(literal)} OK")
      []
    else
      [violation(validator, literal, literal, opts) <> " (nor a state field)"]
    end
  end

  defp violation("regex", path, value, %{pattern: pattern}),
    do: "regex '#{path}': #{inspect(value)} does not match #{inspect(pattern)}"

  defp violation(validator, path, value, _opts),
    do: "#{validator} '#{path}': #{inspect(value)} is not a valid #{validator}"

  # Walks the dot path through the state; lists fan out to every element, so
  # `rows.email` validates the email of each row.
  defp resolve(list, path) when is_list(list), do: Enum.flat_map(list, &resolve(&1, path))
  defp resolve(value, []), do: [value]
  defp resolve(map, [key | rest]) when is_map(map), do: resolve(Map.get(map, key), rest)
  defp resolve(_other, _path), do: [nil]

  # ── Validators ─────────────────────────────────────────────────────────────────

  defp valid?("email", value, _opts) when is_binary(value),
    do: Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, value)

  defp valid?("cpf", value, _opts), do: valid_cpf?(digits(value))
  defp valid?("cnpj", value, _opts), do: valid_cnpj?(value)

  # 8 digits, hyphen optional: "01310-100" or "01310100".
  defp valid?("cep", value, _opts) when is_binary(value),
    do: value |> String.replace(~r/[-.\s]/, "") |> String.match?(~r/^\d{8}$/)

  # Brazilian phone: optional +55, DDD (two non-zero digits), then a 9-digit
  # mobile starting with 9 or an 8-digit landline starting with 2–5.
  defp valid?("telefone", value, _opts) when is_binary(value) do
    value
    |> String.replace(~r/[()\-.\s]/, "")
    |> String.match?(~r/^(?:\+?55)?[1-9][1-9](?:9\d{8}|[2-5]\d{7})$/)
  end

  defp valid?("regex", value, %{re: re}) when is_binary(value), do: Regex.match?(re, value)

  defp valid?(_validator, _value, _opts), do: false

  # ── CPF (numeric only) ─────────────────────────────────────────────────────────

  # Accepts formatted ("123.456.789-09") or bare strings; integers lose leading
  # zeros, so documents must arrive as strings.
  defp digits(value) when is_binary(value),
    do: value |> strip_document() |> String.graphemes() |> parse_digits()

  defp digits(_value), do: nil

  defp parse_digits(graphemes) do
    if Enum.all?(graphemes, &(&1 =~ ~r/^\d$/)),
      do: Enum.map(graphemes, &String.to_integer/1),
      else: nil
  end

  defp strip_document(value), do: String.replace(value, ~r/[.\-\/\s]/, "")

  defp valid_cpf?(ds) when is_list(ds) and length(ds) == 11 do
    Enum.uniq(ds) != [hd(ds)] and
      check_digit(Enum.take(ds, 9), Enum.to_list(10..2//-1)) == Enum.at(ds, 9) and
      check_digit(Enum.take(ds, 10), Enum.to_list(11..2//-1)) == Enum.at(ds, 10)
  end

  defp valid_cpf?(_ds), do: false

  # CPF: weighted sum with descending weights; digit = (sum * 10) rem 11 rem 10.
  defp check_digit(ds, weights) do
    sum = ds |> Enum.zip(weights) |> Enum.map(fn {d, w} -> d * w end) |> Enum.sum()
    rem(rem(sum * 10, 11), 10)
  end

  # ── CNPJ (numeric or alphanumeric, per the 2026 format) ────────────────────────

  # 12 alphanumeric positions + 2 numeric check digits. Each position's value
  # for the mod-11 sum is its ASCII code minus 48 ('0'→0 … '9'→9, 'A'→17 …
  # 'Z'→42), which reduces to the classic algorithm for all-numeric CNPJs.
  defp valid_cnpj?(value) when is_binary(value) do
    normalized = value |> strip_document() |> String.upcase()
    chars = String.to_charlist(normalized)

    Regex.match?(~r/^[A-Z0-9]{12}[0-9]{2}$/, normalized) and
      Enum.uniq(chars) != [hd(chars)] and
      cnpj_check_digits_ok?(Enum.map(chars, &(&1 - ?0)))
  end

  defp valid_cnpj?(_value), do: false

  defp cnpj_check_digits_ok?(values) do
    w1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    w2 = [6 | w1]

    cnpj_digit(Enum.take(values, 12), w1) == Enum.at(values, 12) and
      cnpj_digit(Enum.take(values, 13), w2) == Enum.at(values, 13)
  end

  # CNPJ: digit = 0 when sum rem 11 < 2, else 11 - (sum rem 11).
  defp cnpj_digit(values, weights) do
    sum = values |> Enum.zip(weights) |> Enum.map(fn {v, w} -> v * w end) |> Enum.sum()

    case rem(sum, 11) do
      r when r < 2 -> 0
      r -> 11 - r
    end
  end
end
