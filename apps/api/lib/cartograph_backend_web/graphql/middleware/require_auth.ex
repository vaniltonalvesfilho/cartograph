defmodule CartographBackendWeb.Graphql.Middleware.RequireAuth do
  @moduledoc """
  Fail-closed authentication gate prepended to every root field of the schema
  (see `CartographBackendWeb.Schema.middleware/3`).

  The HTTP pipeline already runs `RequireAuth`/`AbsintheContext` plugs, but the
  schema itself must not depend on any particular transport: GraphiQL (dev) and
  future entry points bypass the router pipeline. Resolvers keep doing the
  fine-grained authorization; this middleware only guarantees no field ever
  resolves without an authenticated user in the context.
  """

  @behaviour Absinthe.Middleware

  @impl true
  def call(%{context: %{current_user: user}} = resolution, _opts) when not is_nil(user),
    do: resolution

  def call(resolution, _opts),
    do: Absinthe.Resolution.put_result(resolution, {:error, "unauthorized"})
end
