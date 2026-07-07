defmodule CartographBackend.Steps.NotifyStepTest do
  # NOT async: swaps the Slack HTTP client for the fake via the app env.
  use CartographBackend.DataCase, async: false

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Groups.{Group, Project}
  alias CartographBackend.Steps.NotifyStep
  alias CartographBackend.Webhooks
  alias CartographBackend.Webhooks.SlackHttpClientFake

  @url "https://hooks.slack.com/services/T000/B000/XXXX"

  setup do
    Application.put_env(:cartograph_backend, :slack_http_client, SlackHttpClientFake)
    Application.put_env(:cartograph_backend, :slack_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:cartograph_backend, :slack_http_client)
      Application.delete_env(:cartograph_backend, :slack_test_pid)
      Application.delete_env(:cartograph_backend, :slack_fake_response)
    end)

    group = %Group{} |> Group.changeset(%{name: "infra"}) |> Repo.insert!()

    project =
      %Project{} |> Project.changeset(%{name: "Linux", group_id: group.id}) |> Repo.insert!()

    {:ok, webhook} =
      Webhooks.create(%{"name" => "alerts", "url" => @url, "project_id" => project.id})

    %{project: project, webhook: webhook}
  end

  defp ctx(params, project_id) do
    %StepContext{
      params: params,
      state: %{},
      execution_id: 999_999,
      step_execution_id: 1,
      project_id: project_id,
      log: fn _level, _msg -> :ok end,
      cancelled?: fn -> false end
    }
  end

  test "posts the given message to the decrypted webhook URL", %{project: p, webhook: w} do
    params = %{"secret" => w.code, "message" => "Daily load finished"}
    assert {:ok, _} = NotifyStep.execute(ctx(params, p.id))

    assert_receive {:slack_post, @url, body}
    assert Jason.decode!(body) == %{"text" => "Daily load finished"}
  end

  test "without message a default line naming the execution is sent", %{project: p, webhook: w} do
    assert {:ok, _} = NotifyStep.execute(ctx(%{"secret" => w.code}, p.id))

    assert_receive {:slack_post, @url, body}
    assert Jason.decode!(body)["text"] =~ "execution #999999"
  end

  test "missing secret param fails before any lookup", %{project: p} do
    assert {:error, msg} = NotifyStep.execute(ctx(%{}, p.id))
    assert msg =~ "'secret' param is required"
    refute_receive {:slack_post, _, _}
  end

  test "unknown code and another project's webhook fail with the same message", %{
    project: p,
    webhook: w
  } do
    assert {:error, unknown} = NotifyStep.execute(ctx(%{"secret" => "slack-00000000"}, p.id))

    other =
      %Project{} |> Project.changeset(%{name: "Outro", group_id: nil}) |> Repo.insert!()

    assert {:error, foreign} = NotifyStep.execute(ctx(%{"secret" => w.code}, other.id))

    assert unknown == String.replace(foreign, w.code, "slack-00000000")
    refute_receive {:slack_post, _, _}
  end

  test "a delivery failure surfaces as a step error", %{project: p, webhook: w} do
    Application.put_env(:cartograph_backend, :slack_fake_response, {:error, "HTTP 404: no_service"})

    assert {:error, msg} = NotifyStep.execute(ctx(%{"secret" => w.code}, p.id))
    assert msg =~ "Slack delivery failed: HTTP 404"
  end
end
