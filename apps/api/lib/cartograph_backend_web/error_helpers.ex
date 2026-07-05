defmodule CartographBackendWeb.ErrorHelpers do
  @moduledoc """
  Shared helpers for building consistent JSON error responses across controllers.

  Validation (changeset) failures use status 422 with a field-keyed map so the
  client can surface per-field messages:

      %{errors: %{"name" => ["can't be blank"]}}

  Other failures use a flat message with an appropriate status, e.g.
  `%{error: "Forbidden"}` with 403.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @doc """
  Turns a changeset into a `field => [messages]` map, interpolating placeholders
  such as `%{count}` into the final message (so counts/limits are not leaked
  verbatim to the client).
  """
  def changeset_messages(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r/%{(\w+)}/, msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc "422 Unprocessable Entity with field-keyed validation messages."
  def unprocessable(conn, %Ecto.Changeset{} = changeset) do
    conn |> put_status(422) |> json(%{errors: changeset_messages(changeset)})
  end

  @doc "403 Forbidden."
  def forbidden(conn), do: conn |> put_status(403) |> json(%{error: "Forbidden"})

  @doc """
  `:ok` if the request's user is a global admin, otherwise `{:error, conn}` with a
  403 already rendered — for `with :ok <- require_admin(conn)` chains whose else
  clause returns the conn.
  """
  def require_admin(%{assigns: %{current_user: %{is_admin: true}}}), do: :ok
  def require_admin(conn), do: {:error, forbidden(conn)}

  @doc "400 Bad request."
  def bad_request(conn), do: conn |> put_status(400) |> json(%{error: "Bad request"})
end
