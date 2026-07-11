defmodule CartographBackend.Agents.Pricing do
  @moduledoc """
  Estimated cost of an Anthropic API call, in USD, from a hardcoded price
  table. Informational, not billing — the UI labels the number "estimated".
  Unknown models return `nil` (tokens are still recorded, nothing blocks).

  Updated: 2026-07-08.
  """

  # {input USD per million tokens, output USD per million tokens}
  @prices %{
    "claude-opus-4-8" => {5.00, 25.00},
    "claude-opus-4-7" => {5.00, 25.00},
    "claude-opus-4-6" => {5.00, 25.00},
    "claude-sonnet-5" => {3.00, 15.00},
    "claude-sonnet-4-6" => {3.00, 15.00},
    "claude-haiku-4-5" => {1.00, 5.00},
    "claude-fable-5" => {10.00, 50.00}
  }

  @spec estimate(String.t(), non_neg_integer(), non_neg_integer()) :: float() | nil
  def estimate(model, input_tokens, output_tokens) do
    case Map.get(@prices, model) do
      nil ->
        nil

      {input_price, output_price} ->
        (input_tokens * input_price + output_tokens * output_price) / 1_000_000
    end
  end
end
