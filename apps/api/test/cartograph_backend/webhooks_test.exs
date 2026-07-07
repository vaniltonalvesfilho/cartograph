defmodule CartographBackend.WebhooksTest do
  use CartographBackend.DataCase, async: true

  alias CartographBackend.{Vault, Webhooks}
  alias CartographBackend.Groups.{Group, Project}

  @url "https://hooks.slack.com/services/T000/B000/XXXX"

  defp insert_project do
    group = %Group{} |> Group.changeset(%{name: "infra"}) |> Repo.insert!()
    %Project{} |> Project.changeset(%{name: "Linux", group_id: group.id}) |> Repo.insert!()
  end

  defp create!(project, attrs \\ %{}) do
    {:ok, webhook} =
      Webhooks.create(Map.merge(%{"name" => "alerts", "url" => @url, "project_id" => project.id}, attrs))

    webhook
  end

  test "create generates a slack-<suffix> code and encrypts the URL" do
    webhook = create!(insert_project())

    assert webhook.code =~ ~r/^slack-[A-Za-z0-9]{8}$/
    assert webhook.url_encrypted != @url
    assert Vault.decrypt(webhook.url_encrypted) == @url
  end

  test "only Slack incoming webhook URLs are accepted (SSRF guard)" do
    project = insert_project()

    for bad <- ["http://hooks.slack.com/x", "https://example.com/hook", "https://hooks.slack.com.evil.com/x"] do
      {:error, cs} = Webhooks.create(%{"name" => "w", "url" => bad, "project_id" => project.id})
      assert %{url: [_ | _]} = errors_on(cs)
    end
  end

  test "name is unique within the project, free across projects" do
    project = insert_project()
    create!(project)

    {:error, cs} = Webhooks.create(%{"name" => "alerts", "url" => @url, "project_id" => project.id})
    assert %{project_id: ["already used in this project"]} = errors_on(cs)

    other = insert_project()
    assert %{} = create!(other)
  end

  test "update keeps the stored URL when none is sent and never changes the code" do
    webhook = create!(insert_project())

    {:ok, updated} = Webhooks.update(webhook, %{"name" => "renamed", "url" => ""})

    assert updated.name == "renamed"
    assert updated.code == webhook.code
    assert Vault.decrypt(updated.url_encrypted) == @url
  end

  test "get_by_code resolves and list_for_project scopes by project" do
    project = insert_project()
    webhook = create!(project)
    _other = create!(insert_project(), %{"name" => "other"})

    assert {:ok, found} = Webhooks.get_by_code(webhook.code)
    assert found.id == webhook.id
    assert {:error, :not_found} = Webhooks.get_by_code("slack-00000000")

    assert [only] = Webhooks.list_for_project(project.id)
    assert only.id == webhook.id
  end
end
