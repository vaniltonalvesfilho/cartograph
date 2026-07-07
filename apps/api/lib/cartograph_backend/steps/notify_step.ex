defmodule CartographBackend.Steps.NotifyStep do
  @moduledoc """
  Posts a message to a Slack incoming webhook registered on the project.

      step "notify" {
          secret "slack-uI0IOQ45",
          message "Daily load finished"
      }

  `secret` is the public code of a webhook registered on the executing
  project — webhooks from other projects are not reachable, and the "not
  found" and "wrong project" cases share one error message so codes cannot
  be enumerated. `message` is optional; without it a default line naming
  the job and execution is sent. The webhook URL is the secret itself: it
  is decrypted only at delivery time and never logged.
  """
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.{Executions, Vault, Webhooks}
  alias CartographBackend.Webhooks.SlackHttpClient

  @impl true
  def name, do: "notify"

  @impl true
  def execute(%StepContext{params: params, project_id: project_id} = ctx) do
    code = Map.get(params, "secret")

    with {:secret, true}       <- {:secret, is_binary(code) and code != ""},
         {:hook, {:ok, hook}}  <- {:hook, Webhooks.get_by_code(code)},
         {:access, true}       <- {:access, hook.project_id == project_id},
         {:post, :ok}          <- {:post, deliver(hook, message(params, ctx))} do
      StepContext.info(ctx, "notify: message sent to Slack webhook '#{hook.name}' (#{code})")
      {:ok, ctx}
    else
      {:secret, false} ->
        {:error, "notify: 'secret' param is required (the webhook code, e.g. slack-uI0IOQ45)"}

      {:hook, {:error, _}} ->
        {:error, not_accessible(code)}

      {:access, false} ->
        {:error, not_accessible(code)}

      {:post, {:error, reason}} ->
        {:error, "notify: Slack delivery failed: #{reason}"}
    end
  end

  defp not_accessible(code),
    do: "notify: Slack webhook '#{code}' not found in this project"

  defp message(%{"message" => msg}, _ctx) when is_binary(msg) and msg != "", do: msg
  defp message(_params, ctx), do: default_message(ctx)

  defp default_message(%StepContext{execution_id: execution_id}) do
    case Executions.get_execution(execution_id) do
      {:ok, %{execution: execution}} ->
        "Cartograph: job '#{execution.task_name}' (execution ##{execution_id})"

      _ ->
        "Cartograph: execution ##{execution_id}"
    end
  end

  defp deliver(hook, message) do
    url = Vault.decrypt(hook.url_encrypted)
    SlackHttpClient.impl().post(url, Jason.encode!(%{text: message}))
  end
end
