defmodule CartographBackend.Steps.TransformStepSecurityTest do
  use CartographBackend.DataCase, async: false

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Steps.TransformStep

  setup do
    group = %Group{} |> Group.changeset(%{name: "g"}) |> Repo.insert!()
    project = %Project{} |> Project.changeset(%{name: "p", group_id: group.id}) |> Repo.insert!()
    %{project: project}
  end

  defp ctx(state, project_id) do
    %StepContext{
      params: %{"operation" => "lowercase"},
      state: state,
      execution_id: 1,
      step_execution_id: 1,
      project_id: project_id,
      log: fn _, _ -> :ok end,
      cancelled?: fn -> false end
    }
  end

  # Regression: state["files"] is not a param, so it never went through
  # SafePath — any step that writes state (parseJson takes a model-chosen
  # result_key) could turn transform into an arbitrary file read.
  test "refuses a path outside the project sandbox", %{project: p} do
    assert {:error, reason} =
             TransformStep.execute(ctx(%{"files" => ["/etc/hostname"]}, p.id))

    assert reason =~ "outside the allowed data directory"
  end

  test "refuses traversal out of the project sandbox", %{project: p} do
    assert {:error, reason} =
             TransformStep.execute(ctx(%{"files" => ["../../../../etc/passwd"]}, p.id))

    assert reason =~ "outside the allowed data directory"
  end

  test "refuses another project's sandbox", %{project: p} do
    other = "/tmp/x/projects/#{p.id + 1}/secret.json"
    assert {:error, _} = TransformStep.execute(ctx(%{"files" => [other]}, p.id))
  end
end
