defmodule CartographBackend.Dsl.Flow do
  @moduledoc """
  Builds a **visualizable execution flow** for a job: the ordered tree of steps,
  branches and inlined sub-jobs, WITHOUT flattening (unlike `Expander`).

  Where the `Expander` collapses `use` refs into a flat step list for execution,
  `Flow` keeps the structure so a UI can show *where* each step comes from — a
  referenced job's steps stay grouped under a `job` node carrying its name/code.

  Conditions are not evaluated; if/else branches are emitted as-is so both paths
  are shown.

  ## Node shapes (plain maps, JSON-ready)

  Every node carries a **stable `id`** — its structural path from the root
  (`"0"`, `"1/t0"` for the 1st then-branch child, `"2/j0"` for a sub-job's 1st
  child, …). The id is deterministic for a given DSL, so a graph node correlates
  with the runtime step that ran it (see project_graph_viz_plan).

      %{"id" => id, "kind" => "step", "name" => name, "params" => params}
      %{"id" => id, "kind" => "if", "condition" => text, "then" => [node], "else" => [node]}
      %{"id" => id, "kind" => "job", "ref" => code, "name" => name, "taskId" => tid,
        "cycle" => bool, "steps" => [node]}
      %{"id" => id, "kind" => "job_error", "ref" => code}   # unresolved/forbidden ref

  ## Authorization

  Same model as `Expander`: a real `%{user: user}` ctx authorizes `:view` on each
  referenced job; an unauthorized/nonexistent ref becomes a `job_error` node (the
  generic outcome — no enumeration oracle). `:system` skips the check.
  """

  alias CartographBackend.Dsl.{Parser, StepSpec, IfNode, RefResolver}
  alias CartographBackend.Tasks.TaskDefinition

  @job_meta "__job__"
  @max_depth 20

  @type ctx :: %{optional(:user) => any()} | :system

  @doc """
  Builds the flow tree for a job's DSL source.

  Returns `{:ok, [node]}` or `{:error, reason}` when the *top-level* DSL fails to
  parse. Broken/forbidden sub-job refs do NOT fail the build — they surface as
  `job_error` nodes so the rest of the flow still renders.

  Pass the job's own `code` as `self_code` so a direct self-reference is detected
  at the top level (shown as a `cycle` node instead of expanding once).
  """
  @spec build(String.t() | nil, ctx, String.t() | nil) :: {:ok, [map()]} | {:error, String.t()}
  # No default ctx: the privileged :system bypass must always be explicit.
  def build(dsl, ctx, self_code \\ nil) do
    case Parser.parse(dsl) do
      {:ok, parsed} ->
        visited = if self_code, do: MapSet.new([self_code]), else: MapSet.new()
        {:ok, walk(parsed.steps, normalize_ctx(ctx), visited, 0, "")}

      {:error, _} = err ->
        err
    end
  end

  # ── ctx ───────────────────────────────────────────────────────────────────────

  defp normalize_ctx(:system), do: %{user: :system}
  defp normalize_ctx(%{} = ctx), do: Map.merge(%{user: nil}, ctx)

  # ── Walk ──────────────────────────────────────────────────────────────────────

  # `prefix` is the id stem for this level; each node's id is `"#{prefix}#{index}"`.
  defp walk(nodes, ctx, visited, depth, prefix) do
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {n, i} -> node(n, ctx, visited, depth, "#{prefix}#{i}") end)
  end

  defp node(%StepSpec{name: @job_meta, params: %{"ref" => code}}, ctx, visited, depth, id) do
    job_node(code, ctx, visited, depth, id)
  end

  defp node(%StepSpec{name: name, params: params}, _ctx, _visited, _depth, id) do
    %{"id" => id, "kind" => "step", "name" => name, "params" => params || %{}}
  end

  defp node(%IfNode{} = n, ctx, visited, depth, id) do
    %{
      "id" => id,
      "kind" => "if",
      "condition" => describe(n.condition),
      "then" => walk(n.then_steps, ctx, visited, depth + 1, "#{id}/t"),
      "else" => walk(n.else_steps, ctx, visited, depth + 1, "#{id}/e")
    }
  end

  # ── Sub-job resolution ────────────────────────────────────────────────────────

  defp job_node(code, _ctx, _visited, depth, id) when depth >= @max_depth do
    %{
      "id" => id,
      "kind" => "job",
      "ref" => code,
      "name" => code,
      "taskId" => nil,
      "cycle" => true,
      "steps" => []
    }
  end

  defp job_node(code, ctx, visited, depth, id) when is_binary(code) do
    cond do
      MapSet.member?(visited, code) ->
        # Already on the current path: show the group but don't recurse (cycle).
        with %TaskDefinition{} = task <- resolve(code, ctx) do
          job_group(task, code, [], true, id)
        else
          _ -> %{"id" => id, "kind" => "job_error", "ref" => code}
        end

      true ->
        case resolve(code, ctx) do
          %TaskDefinition{} = task ->
            steps =
              case Parser.parse(task.dsl) do
                {:ok, parsed} ->
                  walk(parsed.steps, ctx, MapSet.put(visited, code), depth + 1, "#{id}/j")

                {:error, _} ->
                  []
              end

            job_group(task, code, steps, false, id)

          _ ->
            %{"id" => id, "kind" => "job_error", "ref" => code}
        end
    end
  end

  defp job_node(code, _ctx, _visited, _depth, id),
    do: %{"id" => id, "kind" => "job_error", "ref" => code}

  defp job_group(%TaskDefinition{} = task, code, steps, cycle?, id) do
    %{
      "id" => id,
      "kind" => "job",
      "ref" => task.code || code,
      "name" => task.name,
      "taskId" => task.id,
      "cycle" => cycle?,
      "steps" => steps
    }
  end

  # Resolve globally by code with :view auth (system bypasses) via RefResolver.
  # Returns the task or nil — callers turn nil into the generic job_error node.
  defp resolve(code, ctx) do
    case RefResolver.resolve(code, ctx) do
      {:ok, task} -> task
      :error -> nil
    end
  end

  # ── Condition rendering ───────────────────────────────────────────────────────

  defp describe({:literal, v}) when is_binary(v), do: ~s("#{v}")
  defp describe({:literal, v}), do: to_string(v)
  defp describe({:state_get, k}), do: ~s(state["#{k}"])
  defp describe({:compare, op, l, r}), do: "#{describe(l)} #{op_text(op)} #{describe(r)}"
  defp describe({:logical, :not, e}), do: "not #{describe(e)}"
  defp describe({:logical, op, [a, b]}), do: "(#{describe(a)} #{op} #{describe(b)})"
  defp describe(other), do: inspect(other)

  defp op_text(:eq), do: "=="
  defp op_text(:neq), do: "!="
  defp op_text(:gt), do: ">"
  defp op_text(:lt), do: "<"
  defp op_text(:gte), do: ">="
  defp op_text(:lte), do: "<="
end
