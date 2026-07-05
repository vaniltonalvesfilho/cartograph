defmodule CartographBackend.Mailing.Emails do
  @moduledoc """
  Builds the application's outbound emails as `Swoosh.Email` structs.

  These do NOT set the `from` address — `CartographBackend.Mailing.deliver/1`
  fills it in from the saved SMTP settings so the sender stays consistent.
  """
  import Swoosh.Email

  @doc "Welcome email sent to a newly created user."
  def welcome(user) do
    new()
    |> to({user.name, user.email})
    |> subject("Welcome to Cartograph")
    |> text_body("""
    Hi #{user.name},

    Your Cartograph account has been created. You can now sign in to the
    platform with the email #{user.email}.

    — Cartograph
    """)
  end

  @doc """
  Notification sent when a job execution fails. `recipients` is a list of
  email addresses; each gets an individual copy (no shared To/CC, to avoid
  leaking the recipient list).
  """
  def execution_failure(execution, recipient) do
    new()
    |> to(recipient)
    |> subject("Execution failed: #{execution.task_name}")
    |> text_body("""
    The execution of job "#{execution.task_name}" failed.

    Execution: ##{execution.id}
    Status:    #{execution.status}
    Started:   #{execution.started_at}
    Finished:  #{execution.finished_at}

    Open Cartograph to see the full logs.

    — Cartograph
    """)
  end

  @doc "Test email, sent only to the requesting admin's own address."
  def test(recipient) do
    new()
    |> to(recipient)
    |> subject("Cartograph — test email")
    |> text_body("""
    This is a test email from Cartograph.

    If you received this message, your SMTP configuration is working.

    — Cartograph
    """)
  end
end
