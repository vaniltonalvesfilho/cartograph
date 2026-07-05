defmodule CartographBackend.Executions.Status do
  @moduledoc """
  Canonical execution and step status values. Statuses are persisted as strings;
  reference these helpers instead of scattering literals.

      PENDING → queued, not started yet
      RUNNING → in progress
      SUCCESS → finished OK
      FAILED  → finished with an error
      STOPPED → cancelled by a stop request
      SKIPPED → a step an if/else branch did not take
  """

  @pending "PENDING"
  @running "RUNNING"
  @success "SUCCESS"
  @failed "FAILED"
  @stopped "STOPPED"
  @skipped "SKIPPED"

  def pending, do: @pending
  def running, do: @running
  def success, do: @success
  def failed, do: @failed
  def stopped, do: @stopped
  def skipped, do: @skipped

  @active [@pending, @running]
  @terminal [@success, @failed, @stopped]

  @doc "Statuses of an execution still in progress (queued or running)."
  def active, do: @active

  @doc "Statuses of a finished execution (success, failed or stopped)."
  def terminal, do: @terminal

  @doc "True if the execution is queued or running."
  def active?(status), do: status in @active

  @doc "True if the execution has finished (success, failed or stopped)."
  def terminal?(status), do: status in @terminal
end
