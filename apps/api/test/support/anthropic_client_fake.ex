defmodule CartographBackend.Agents.AnthropicClientFake do
  @moduledoc """
  Test double for the Anthropic Messages API — the suite must never spend
  real tokens. Captures each call by messaging the test process registered in
  `:anthropic_test_pid`; the reply defaults to a canned successful response
  and can be forced with `:anthropic_fake_response`.
  """

  @behaviour CartographBackend.Agents.AnthropicClient

  @impl true
  def create_message(api_key, body) do
    if pid = Application.get_env(:cartograph_backend, :anthropic_test_pid) do
      send(pid, {:anthropic_create_message, api_key, body})
    end

    Application.get_env(:cartograph_backend, :anthropic_fake_response, default_response())
  end

  def default_response do
    {:ok,
     %{
       "model" => "claude-opus-4-8",
       "stop_reason" => "end_turn",
       "content" => [%{"type" => "text", "text" => "Fake agent answer."}],
       "usage" => %{"input_tokens" => 12, "output_tokens" => 34}
     }}
  end
end
