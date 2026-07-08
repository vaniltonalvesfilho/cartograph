defmodule CartographBackendWeb.SmtpSettingController do
  use CartographBackendWeb, :controller

  alias CartographBackend.Mailing
  alias CartographBackendWeb.Serializers

  # All endpoints are admin-only. The password is write-only: it is accepted on
  # update but never returned (see Serializers.smtp_settings/1).

  def show(conn, _params) do
    with :ok <- require_admin(conn) do
      json(conn, Serializers.smtp_settings(Mailing.get_settings()))
    else
      {:error, conn} -> conn
    end
  end

  def update(conn, %{"smtp" => attrs}) do
    with :ok <- require_admin(conn) do
      # Drop a blank password so a save without re-typing keeps the stored one.
      attrs = drop_blank_password(attrs)

      case Mailing.upsert_settings(attrs) do
        {:ok, setting} -> json(conn, Serializers.smtp_settings(setting))
        {:error, cs} -> unprocessable(conn, cs)
      end
    else
      {:error, conn} -> conn
    end
  end

  @doc """
  Sends a test email. The recipient is ALWAYS the requesting admin's own email —
  it is not taken from the request body, so this can't be used to probe or spam
  arbitrary addresses.
  """
  def test(conn, _params) do
    with :ok <- require_admin(conn) do
      email = conn.assigns.current_user.email

      # Always reply 200 with a {status, ...} body so the dashboard can show the
      # real reason instead of a generic transport error.
      cond do
        not Mailing.configured?() ->
          json(conn, %{status: "error", error: "SMTP is not configured or enabled"})

        true ->
          case Mailing.send_test(email) do
            {:ok, _} -> json(conn, %{status: "ok", sentTo: email})
            {:error, reason} -> json(conn, %{status: "error", error: humanize_error(reason)})
          end
      end
    else
      {:error, conn} -> conn
    end
  end

  # Turns gen_smtp/Swoosh error tuples into a readable message by pulling out the
  # human-readable parts (e.g. the server's "535 Username and Password not
  # accepted" reply), falling back to inspect/1 for unrecognised shapes.
  defp humanize_error(reason) do
    case reason |> collect_terms() |> Enum.join(": ") do
      "" -> inspect(reason)
      s -> s
    end
  end

  defp collect_terms(t) when is_binary(t), do: [t]

  defp collect_terms(t) when is_atom(t) and t not in [nil, true, false],
    do: [t |> to_string() |> String.replace("_", " ")]

  defp collect_terms(t) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.flat_map(&collect_terms/1)

  defp collect_terms(t) when is_list(t), do: Enum.flat_map(t, &collect_terms/1)
  defp collect_terms(_), do: []

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp drop_blank_password(%{"password" => p} = attrs) when p in [nil, ""],
    do: Map.delete(attrs, "password")

  defp drop_blank_password(attrs), do: attrs
end
