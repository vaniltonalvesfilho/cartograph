defmodule CartographBackend.Agents.AnthropicClient do
  @moduledoc """
  Calls the Anthropic Messages API (`POST /v1/messages`). The implementation
  is read from `config :cartograph_backend, :anthropic_client` so tests can
  swap in a fake — an agent step must never spend real tokens in the test
  suite.

  The base URL is server config only (`:anthropic_base_url`, defaulting to
  `https://api.anthropic.com`) — never user input, so there is no SSRF
  surface. Retry policy: at most one retry, only for 429/500/529 and
  transport errors; 4xx is never retried (LLM calls are expensive and an
  overloaded API must not multiply cost).
  """

  @callback create_message(api_key :: String.t(), body :: map()) ::
              {:ok, map()} | {:error, String.t()}

  def impl, do: Application.get_env(:cartograph_backend, :anthropic_client, __MODULE__)

  @behaviour __MODULE__

  @anthropic_version "2023-06-01"
  @retryable_statuses [429, 500, 529]
  @error_detail_limit 300

  @impl true
  def create_message(api_key, body) when is_binary(api_key) and is_map(body) do
    request(api_key, Jason.encode!(body), _attempt = 1)
  end

  defp request(api_key, json_body, attempt) do
    url = base_url() <> "/v1/messages"

    headers = [
      {~c"x-api-key", String.to_charlist(api_key)},
      {~c"anthropic-version", String.to_charlist(@anthropic_version)}
    ]

    request = {String.to_charlist(url), headers, ~c"application/json", json_body}
    # Non-streaming LLM responses can take minutes; the Oban :executions jobs
    # driving this call are long-lived already.
    http_opts = [ssl: ssl_opts(), timeout: 240_000, connect_timeout: 10_000]

    case :httpc.request(:post, request, http_opts, body_format: :binary) do
      {:ok, {{_http, status, _phrase}, _headers, resp_body}} when status in 200..299 ->
        decode(resp_body)

      {:ok, {{_http, status, _phrase}, _headers, resp_body}}
      when status in @retryable_statuses ->
        retry_or_fail(api_key, json_body, attempt, error_detail(status, resp_body))

      {:ok, {{_http, status, _phrase}, _headers, resp_body}} ->
        {:error, error_detail(status, resp_body)}

      {:error, reason} ->
        retry_or_fail(api_key, json_body, attempt, inspect(reason))
    end
  end

  defp retry_or_fail(api_key, json_body, 1, _detail) do
    backoff()
    request(api_key, json_body, 2)
  end

  defp retry_or_fail(_api_key, _json_body, _attempt, detail), do: {:error, detail}

  defp decode(resp_body) do
    case Jason.decode(resp_body) do
      {:ok, map} -> {:ok, map}
      {:error, _} -> {:error, "invalid JSON in Anthropic API response"}
    end
  end

  # Prefers the API's own `error.message`; falls back to the raw body,
  # truncated so a huge error page never floods the step error.
  defp error_detail(status, resp_body) do
    message =
      case Jason.decode(resp_body) do
        {:ok, %{"error" => %{"message" => msg}}} when is_binary(msg) -> msg
        _ -> to_string(resp_body)
      end

    "HTTP #{status}: #{String.slice(message, 0, @error_detail_limit)}"
  end

  defp backoff, do: Process.sleep(2_000 + :rand.uniform(1_000))

  defp base_url do
    Application.get_env(:cartograph_backend, :anthropic_base_url, "https://api.anthropic.com")
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
