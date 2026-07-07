defmodule CartographBackend.Webhooks.SlackHttpClientFake do
  @moduledoc """
  Test double for Slack delivery — the suite must never post to a real
  webhook. Captures each call by messaging the test process registered in
  `:slack_test_pid`; the reply defaults to `:ok` and can be forced with
  `:slack_fake_response`.
  """

  @behaviour CartographBackend.Webhooks.SlackHttpClient

  @impl true
  def post(url, json_body) do
    if pid = Application.get_env(:cartograph_backend, :slack_test_pid) do
      send(pid, {:slack_post, url, json_body})
    end

    Application.get_env(:cartograph_backend, :slack_fake_response, :ok)
  end
end
