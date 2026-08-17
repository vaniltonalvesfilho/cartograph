defmodule CartographBackend.Steps.DatabaseAccessTest do
  # The database steps gate on the data source being assigned to the running
  # job's project. These tests only exercise that gate — they never reach a
  # connection, so no real database is contacted.
  use CartographBackend.DataCase, async: true

  alias CartographBackend.DataSources
  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Steps.{ExecuteDatabaseStep, QueryDatabaseStep}

  defp ctx(project_id, params) do
    %StepContext{
      params: params,
      state: %{},
      execution_id: 1,
      step_execution_id: 1,
      project_id: project_id,
      log: fn _level, _msg -> :ok end,
      cancelled?: fn -> false end
    }
  end

  defp insert_project do
    g = %Group{} |> Group.changeset(%{name: "root"}) |> Repo.insert!()
    %Project{} |> Project.changeset(%{name: "proj", group_id: g.id}) |> Repo.insert!()
  end

  defp insert_data_source do
    {:ok, ds} =
      DataSources.create(%{
        "name" => "prod",
        "slug" => "prod-db",
        "adapter" => "postgres",
        "host" => "127.0.0.1",
        "port" => 1,
        "database_name" => "prod",
        "username" => "u",
        "password" => "p"
      })

    ds
  end

  test "a job with no project reaches no data source" do
    ds = insert_data_source()
    project = insert_project()
    :ok = DataSources.assign_to_project(ds.id, project.id)

    # Even a source assigned to some project is out of reach: a project-less job
    # is assigned nothing, so it must not inherit access to everything.
    assert {:error, msg} =
             QueryDatabaseStep.execute(ctx(nil, %{"source" => "prod-db", "query" => "SELECT 1"}))

    assert msg =~ "not accessible"

    assert {:error, msg} =
             ExecuteDatabaseStep.execute(
               ctx(nil, %{"source" => "prod-db", "query" => "DELETE FROM t"})
             )

    assert msg =~ "not accessible"
  end

  test "a job only reaches data sources assigned to its project" do
    ds = insert_data_source()
    project = insert_project()
    other = insert_project()
    :ok = DataSources.assign_to_project(ds.id, other.id)

    refute DataSources.project_has_access?(project.id, ds.id)

    assert {:error, msg} =
             QueryDatabaseStep.execute(
               ctx(project.id, %{"source" => "prod-db", "query" => "SELECT 1"})
             )

    assert msg =~ "not accessible"
  end
end
