defmodule CartographBackend.AgentsTest do
  use CartographBackend.DataCase, async: true

  alias CartographBackend.{Agents, Vault}
  alias CartographBackend.Agents.Pricing
  alias CartographBackend.Groups.{Group, Project}

  @api_key "sk-ant-api03-test-0123456789"

  defp insert_project do
    group = %Group{} |> Group.changeset(%{name: "infra"}) |> Repo.insert!()
    %Project{} |> Project.changeset(%{name: "Linux", group_id: group.id}) |> Repo.insert!()
  end

  defp create!(project, attrs \\ %{}) do
    {:ok, credential} =
      Agents.create(
        Map.merge(
          %{"name" => "prod key", "api_key" => @api_key, "project_id" => project.id},
          attrs
        )
      )

    credential
  end

  test "create generates an anthropic-<suffix> code and encrypts the key" do
    credential = create!(insert_project())

    assert credential.code =~ ~r/^anthropic-[A-Za-z0-9]{8}$/
    assert credential.api_key_encrypted != @api_key
    assert Vault.decrypt(credential.api_key_encrypted) == @api_key
  end

  test "only sk-ant-... keys are accepted" do
    project = insert_project()

    for bad <- ["", "hunter2", "sk-live-abc", "sk-ant-", "sk-ant-has space"] do
      {:error, cs} =
        Agents.create(%{"name" => "k", "api_key" => bad, "project_id" => project.id})

      assert %{api_key: [_ | _]} = errors_on(cs)
    end
  end

  test "name is unique within the project, free across projects" do
    project = insert_project()
    create!(project)

    {:error, cs} =
      Agents.create(%{"name" => "prod key", "api_key" => @api_key, "project_id" => project.id})

    assert %{project_id: ["already used in this project"]} = errors_on(cs)

    other = insert_project()
    assert %{} = create!(other)
  end

  test "update keeps the stored key when none is sent and never changes the code" do
    credential = create!(insert_project())

    {:ok, updated} = Agents.update(credential, %{"name" => "renamed", "api_key" => ""})

    assert updated.name == "renamed"
    assert updated.code == credential.code
    assert Vault.decrypt(updated.api_key_encrypted) == @api_key
  end

  test "get_credential_by_code resolves and list_for_project scopes by project" do
    project = insert_project()
    credential = create!(project)
    _other = create!(insert_project(), %{"name" => "other"})

    assert {:ok, found} = Agents.get_credential_by_code(credential.code)
    assert found.id == credential.id
    assert {:error, :not_found} = Agents.get_credential_by_code("anthropic-00000000")

    assert [only] = Agents.list_for_project(project.id)
    assert only.id == credential.id
  end

  describe "Pricing.estimate/3" do
    test "computes USD from the per-million-token table" do
      # claude-opus-4-8: $5/MTok in, $25/MTok out
      assert Pricing.estimate("claude-opus-4-8", 1_000_000, 0) == 5.0
      assert Pricing.estimate("claude-opus-4-8", 0, 1_000_000) == 25.0
      assert Pricing.estimate("claude-haiku-4-5", 2_000, 1_000) == 0.007
    end

    test "unknown models produce no estimate" do
      assert Pricing.estimate("claude-next-99", 1_000, 1_000) == nil
    end
  end
end
