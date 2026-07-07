defmodule CartographBackend.Webhooks.SlackHttpClient do
  @moduledoc """
  Delivers a payload to a Slack incoming webhook. The implementation is read
  from `config :cartograph_backend, :slack_http_client` so tests can swap in a
  fake — a notify step must never hit Slack for real in the test suite.
  """

  @callback post(url :: String.t(), json_body :: binary()) :: :ok | {:error, String.t()}

  def impl, do: Application.get_env(:cartograph_backend, :slack_http_client, __MODULE__)

  @behaviour __MODULE__

  @impl true
  def post(url, json_body) do
    request = {String.to_charlist(url), [], ~c"application/json", json_body}
    http_opts = [ssl: ssl_opts(), timeout: 10_000, connect_timeout: 5_000]

    case :httpc.request(:post, request, http_opts, body_format: :binary) do
      {:ok, {{_http, status, _phrase}, _headers, _body}} when status in 200..299 ->
        :ok

      {:ok, {{_http, status, _phrase}, _headers, body}} ->
        {:error, "HTTP #{status}: #{String.slice(to_string(body), 0, 200)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp ssl_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
