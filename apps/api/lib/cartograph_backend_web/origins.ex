defmodule CartographBackendWeb.Origins do
  @moduledoc """
  The browser origins allowed to call this instance, for CORS and for the
  WebSocket origin check.

  The list used to be a literal in the endpoint, which meant a deployment could
  not add its own dashboard origin without editing and recompiling the source —
  and the pressure that creates is to reach for `origins: "*"`, which hands
  every site on the internet an authenticated cross-origin channel.

  Configured as:

      config :cartograph_backend, :allowed_origins, ["https://cartograph.example"]

  In production `config/runtime.exs` fills this from `ALLOWED_ORIGINS`
  (comma-separated), falling back to `https://$PHX_HOST`.
  """

  @doc "The configured origins."
  def list, do: Application.get_env(:cartograph_backend, :allowed_origins, [])

  @doc "Is this origin string allowed?"
  def allowed?(origin) when is_binary(origin), do: origin in list()
  def allowed?(_), do: false

  @doc "Corsica callback, which passes the conn ahead of the origin."
  def allowed?(_conn, origin), do: allowed?(origin)

  @doc """
  Phoenix `check_origin` callback, which hands us a parsed `URI`.

  Rebuilt into `scheme://host[:port]` so it compares equal to the configured
  form. A URI with no scheme or host is not something we can vouch for.
  """
  def allowed_uri?(%URI{scheme: scheme, host: host} = uri)
      when is_binary(scheme) and is_binary(host) do
    port = if uri.port && uri.port != URI.default_port(scheme), do: ":#{uri.port}", else: ""
    allowed?("#{scheme}://#{host}#{port}")
  end

  def allowed_uri?(_), do: false
end
