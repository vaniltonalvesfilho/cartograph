defmodule CartographBackend.Dsl.Expander do
  @moduledoc """
  Expands `use`/`job` job references into the referenced task's steps (inline),
  with authorization, hierarchy validation and cycle detection. IfNode branches
  are traversed recursively so references inside then/else blocks are resolved.

  Conditions are NOT evaluated here — that happens at runtime in the executor.

  ## Reference shape (from the parser)

  `params["ref"]` is the job's public `code` string (`use "backup-uI0IOQ45"` /
  `job "backup-uI0IOQ45"`). Resolution is **global** by exact `code`, and the
  acting user must be authorized (`:view`) on the resolved task.

  ## Authorization context (`ctx`)

      %{user: %User{} | nil, project_id: integer | nil}

  `:system` (or `%{user: :system}`) is a privileged context for cron/server runs
  that skips the `:view` check — references were already vetted at author time.

  All failures — nonexistent job or forbidden — return the **identical generic
  error** so there is no enumeration oracle.
  """

  alias CartographBackend.Dsl.{Parser, StepSpec, IfNode, RefResolver}
  alias CartographBackend.Tasks.TaskDefinition

  @job_meta "__job__"

  # Single generic, fail-closed message for ALL resolution failures (not-found,
  # forbidden) so the user cannot distinguish them.
  @generic_error "Job reference not found or access denied"

  # Guards against runaway expansion: `visited` blocks cycles along a single
  # path, but diamond references (the same job reachable via multiple paths)
  # re-expand and can blow up exponentially. A depth cap bounds recursion and a
  # step budget bounds total output size.
  @max_depth 20
  @max_steps 2_000

  @type ctx :: %{optional(:user) => any(), optional(:project_id) => integer() | nil} | :system

  @doc """
  There is deliberately no `expand/1`: the privileged `:system` context must be
  passed explicitly so a caller can never take the authorization bypass by
  accident. Author-time validation threads the acting user; only server-side
  execution (executor/cron) passes `:system`.

  Each resulting `StepSpec` carries `flow_id`: the structural path of the node
  in `Dsl.Flow`'s tree (same id scheme — "0", "1/t0", "2/j0", …), so the runtime
  can persist which flow node produced each step. The ids are derived from the
  node's position in the ORIGINAL (unexpanded) DSL at every level, which is
  exactly how `Flow` walks; `expander_test.exs` holds the contract test.
  """
  @spec expand([StepSpec.t() | IfNode.t()], ctx) ::
          {:ok, [StepSpec.t() | IfNode.t()]} | {:error, String.t()}
  def expand(nodes, ctx), do: do_expand(nodes, normalize_ctx(ctx), MapSet.new(), 0, "")

  # ── ctx normalization ─────────────────────────────────────────────────────────

  defp normalize_ctx(:system), do: %{user: :system, project_id: nil}
  defp normalize_ctx(%{} = ctx), do: Map.merge(%{user: nil, project_id: nil}, ctx)

  # ── Recursion ─────────────────────────────────────────────────────────────────

  # `prefix` is the flow-id stem for this level; each node's id is
  # `"#{prefix}#{index}"` over the ORIGINAL node list (mirrors Flow.walk/5).
  defp do_expand(_nodes, _ctx, _visited, depth, _prefix) when depth > @max_depth,
    do: {:error, "Job chaining too deep (max #{@max_depth} levels)"}

  defp do_expand(nodes, ctx, visited, depth, prefix) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {node, i}, {:ok, acc} ->
      case expand_node(node, ctx, visited, depth, "#{prefix}#{i}") do
        {:ok, expanded} ->
          merged = acc ++ expanded

          if length(merged) > @max_steps,
            do: {:halt, {:error, "Expanded job exceeds #{@max_steps} steps"}},
            else: {:cont, {:ok, merged}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end

  defp expand_node(%StepSpec{name: @job_meta, params: %{"ref" => ref}}, ctx, visited, depth, id) do
    key = canonical_ref_key(ref, ctx)

    if MapSet.member?(visited, key) do
      {:error, "Circular job reference detected: '#{key}'"}
    else
      resolve_ref(ref, ctx, MapSet.put(visited, key), depth + 1, id)
    end
  end

  defp expand_node(%StepSpec{} = step, _ctx, _visited, _depth, id),
    do: {:ok, [%StepSpec{step | flow_id: id}]}

  defp expand_node(%IfNode{} = node, ctx, visited, depth, id) do
    with {:ok, then_steps} <- do_expand(node.then_steps, ctx, visited, depth + 1, "#{id}/t"),
         {:ok, else_steps} <- do_expand(node.else_steps, ctx, visited, depth + 1, "#{id}/e") do
      {:ok, [%IfNode{node | then_steps: then_steps, else_steps: else_steps}]}
    end
  end

  # ── Canonical cycle key (stable across both ref shapes for the same task) ──────

  @doc """
  Canonical key used for cycle detection. The ref is the job `code`, globally
  unique, so it doubles as the cycle key.
  """
  @spec canonical_ref_key(String.t(), ctx) :: String.t()
  def canonical_ref_key(ref, _ctx) when is_binary(ref), do: ref

  # ── Resolution ────────────────────────────────────────────────────────────────

  # Binary ref: resolve globally by exact `code` (with :view auth) via RefResolver.
  defp resolve_ref(code, ctx, visited, depth, id) when is_binary(code) do
    case RefResolver.resolve(code, ctx) do
      {:ok, task} -> expand_resolved(task, ctx, visited, depth, id)
      :error -> {:error, @generic_error}
    end
  end

  # Parse the resolved task's DSL and recurse so nested `use` refs are inlined.
  # The sub-job's steps live under the referencing node's id ("#{id}/j"), same
  # as Flow's job_node.
  defp expand_resolved(%TaskDefinition{} = task, ctx, visited, depth, id) do
    case Parser.parse(task.dsl) do
      {:error, reason} ->
        # Reachable only after passing auth, so it is not an enumeration vector.
        {:error, "Job reference '#{task.name}' has invalid DSL: #{reason}"}

      {:ok, parsed} ->
        do_expand(parsed.steps, ctx, visited, depth, "#{id}/j")
    end
  end
end
