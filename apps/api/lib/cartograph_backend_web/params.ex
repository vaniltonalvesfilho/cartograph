defmodule CartographBackendWeb.Params do
  @moduledoc """
  Small helpers for safely coercing request params. `String.to_integer/1`
  raises on malformed input (turning a bad path param into a 500); these
  helpers return tagged tuples so controllers can answer 400 instead.
  """

  @doc "Parses an integer param. Returns {:ok, int} or {:error, :bad_request}."
  def int(value) when is_integer(value), do: {:ok, value}

  def int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :bad_request}
    end
  end

  def int(_), do: {:error, :bad_request}
end
