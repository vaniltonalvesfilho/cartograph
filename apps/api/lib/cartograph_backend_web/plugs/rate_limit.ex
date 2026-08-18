defmodule CartographBackendWeb.Plugs.RateLimit do
  @moduledoc """
  Throttles a route by client address, and optionally by a request parameter
  (the account being logged into, the pending 2FA session being verified).

  Both keys are counted on every request: the address limit stops one host
  hammering many accounts, the parameter limit stops a distributed attempt at
  a single account. Whichever trips first wins.

  The client address is `conn.remote_ip` and nothing else. `X-Forwarded-For` is
  attacker-controlled unless a trusted proxy overwrites it, and honouring it
  here would let anyone reset their own counter with a header. Deployments
  behind a proxy should put something like `remote_ip` in the endpoint so
  `conn.remote_ip` is the real address before this plug runs.

  Limits come from config, so they can be tuned per environment:

      config :cartograph_backend, CartographBackendWeb.Plugs.RateLimit,
        login: [address: {60, :timer.minutes(15)}, identifier: {10, :timer.minutes(15)}]
  """

  import Plug.Conn
  require Logger

  alias CartographBackend.RateLimiter

  @behaviour Plug

  @impl true
  def init(opts) do
    scope = Keyword.fetch!(opts, :scope)
    %{scope: scope, identifier_param: Keyword.get(opts, :identifier_param)}
  end

  @impl true
  def call(conn, %{scope: scope, identifier_param: param}) do
    limits = limits_for(scope)

    checks =
      [
        {{scope, :address, address(conn)}, Keyword.get(limits, :address)},
        {{scope, :identifier, identifier(conn, param)}, Keyword.get(limits, :identifier)}
      ]
      |> Enum.reject(fn {{_, _, value}, limit} -> is_nil(value) or is_nil(limit) end)

    Enum.reduce_while(checks, conn, fn {key, {limit, window_ms}}, conn ->
      case RateLimiter.hit(key, limit, window_ms) do
        :ok -> {:cont, conn}
        {:error, retry_after} -> {:halt, reject(conn, scope, retry_after)}
      end
    end)
  end

  @doc """
  Forgets the counters for a scope/identifier pair after the attempt succeeded.
  """
  def reset(scope, identifier) when is_binary(identifier) do
    RateLimiter.reset({scope, :identifier, hash(identifier)})
  end

  def reset(_scope, _identifier), do: :ok

  # ── Internals ────────────────────────────────────────────────────────────────

  defp limits_for(scope) do
    Application.get_env(:cartograph_backend, __MODULE__, [])
    |> Keyword.get(scope, [])
  end

  defp address(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp identifier(_conn, nil), do: nil

  defp identifier(conn, param) do
    case conn.params do
      %{^param => value} when is_binary(value) and value != "" -> hash(value)
      _ -> nil
    end
  end

  # The identifier is an email or a pending-session token; neither belongs in
  # an ETS table that a crash dump would print.
  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp reject(conn, scope, retry_after) do
    Logger.warning(
      "rate limit hit: scope=#{scope} address=#{address(conn)} retry_after=#{retry_after}s"
    )

    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> put_resp_content_type("application/json")
    |> send_resp(
      429,
      Jason.encode!(%{error: "Too many attempts. Try again in #{retry_after} seconds."})
    )
    |> halt()
  end
end
