defmodule CartographBackendWeb.Graphql.RequireAuthTest do
  # Locks the fail-closed gate: no root field resolves without an authenticated
  # user in the context, even fields whose resolver does no check of its own
  # (dashboard_metrics is exactly that case).
  use CartographBackend.DataCase, async: true

  alias CartographBackend.Accounts.User
  alias CartographBackendWeb.Schema

  @metrics_query "{ dashboardMetrics { totalTasks } }"

  defp insert_user do
    %User{}
    |> User.changeset(%{name: "gql", email: "gql@ex.com", password: "secret123"})
    |> Repo.insert!()
  end

  test "root field is rejected without a user in context" do
    assert {:ok, %{errors: [%{message: "unauthorized"}]}} =
             Absinthe.run(@metrics_query, Schema, context: %{})
  end

  test "root field is rejected with a nil user" do
    assert {:ok, %{errors: [%{message: "unauthorized"}]}} =
             Absinthe.run(@metrics_query, Schema, context: %{current_user: nil})
  end

  test "root field resolves for an authenticated user" do
    assert {:ok, %{data: %{"dashboardMetrics" => %{"totalTasks" => total}}}} =
             Absinthe.run(@metrics_query, Schema, context: %{current_user: insert_user()})

    assert is_integer(total)
  end

  test "mutations are gated too" do
    mutation = ~s|mutation { deleteTask(id: "1") }|

    assert {:ok, %{errors: [%{message: "unauthorized"}]}} =
             Absinthe.run(mutation, Schema, context: %{})
  end
end
