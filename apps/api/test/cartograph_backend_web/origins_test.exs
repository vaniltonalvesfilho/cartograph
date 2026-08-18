defmodule CartographBackendWeb.OriginsTest do
  # NOT async: overrides the global allowed-origins config.
  use ExUnit.Case, async: false

  alias CartographBackendWeb.Origins

  setup do
    previous = Application.get_env(:cartograph_backend, :allowed_origins)

    Application.put_env(:cartograph_backend, :allowed_origins, [
      "https://cartograph.example",
      "app://cartograph"
    ])

    on_exit(fn -> Application.put_env(:cartograph_backend, :allowed_origins, previous) end)
    :ok
  end

  test "only configured origins are allowed" do
    assert Origins.allowed?("https://cartograph.example")
    assert Origins.allowed?("app://cartograph")

    refute Origins.allowed?("https://cartograph.example.evil.com")
    refute Origins.allowed?("http://cartograph.example")
    refute Origins.allowed?("null")
    refute Origins.allowed?(nil)
  end

  test "the socket check rebuilds the origin from the parsed URI" do
    assert Origins.allowed_uri?(URI.parse("https://cartograph.example"))
    assert Origins.allowed_uri?(URI.parse("https://cartograph.example:443"))
    assert Origins.allowed_uri?(URI.parse("app://cartograph"))

    refute Origins.allowed_uri?(URI.parse("https://cartograph.example:8443"))
    refute Origins.allowed_uri?(URI.parse("https://evil.example"))
    refute Origins.allowed_uri?(URI.parse("/just/a/path"))
  end

  test "a non-default port has to be configured explicitly" do
    Application.put_env(:cartograph_backend, :allowed_origins, ["http://localhost:4200"])

    assert Origins.allowed_uri?(URI.parse("http://localhost:4200"))
    refute Origins.allowed_uri?(URI.parse("http://localhost"))
    refute Origins.allowed_uri?(URI.parse("http://localhost:4201"))
  end
end
