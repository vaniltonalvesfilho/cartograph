# Demo jobs with cross-references, for testing the dependency-graph edge
# animation. Each job has `delay` steps so it stays RUNNING long enough to see
# the animation in the dashboard graph. Run with:
#
#     mix run priv/repo/seeds_demo.exs
#
# Then open the dashboard / "All Jobs" graph and run any job — its outgoing
# reference edges animate while it is RUNNING.

alias CartographBackend.Tasks

IO.puts("→ Creating demo jobs…")

# DSL builder: a few `delay` steps (≈ duration secs) plus `use` references.
dsl = fn name, refs, secs ->
  uses  = refs |> Enum.map(&"  use \"#{&1}\"") |> Enum.join("\n")
  delays =
    1..secs
    |> Enum.map(fn _ -> "  step \"delay\" { seconds 1 }," end)
    |> Enum.join("\n")

  "#{name} {\n#{if uses != "", do: uses <> "\n", else: ""}#{delays}\n}"
end

create = fn name, identifier, ddsl ->
  case Tasks.create_task(%{"name" => name, "identifier" => identifier, "dsl" => ddsl}, :system) do
    {:ok, t} ->
      IO.puts("   ✓ #{identifier}  →  #{t.code}")
      t

    {:error, reason} ->
      IO.puts("   ✗ #{identifier} FAILED: #{inspect(reason)}")
      raise "seed failed"
  end
end

extract   = create.("Demo — Extract",   "demo-extract",   dsl.("extract",   [], 5))
validate  = create.("Demo — Validate",  "demo-validate",  dsl.("validate",  [extract.code], 5))
transform = create.("Demo — Transform", "demo-transform", dsl.("transform", [validate.code], 5))
load      = create.("Demo — Load",      "demo-load",      dsl.("load",      [transform.code], 5))
_report   = create.("Demo — Report",    "demo-report",    dsl.("report",    [transform.code, load.code], 4))
_notify   = create.("Demo — Notify",    "demo-notify",    dsl.("notify",    [load.code], 4))

IO.puts("""

Done! Dependency graph:

  demo-extract
       │
  demo-validate
       │
  demo-transform ──────────┐
       │                   │
  demo-load           demo-report
       │
  demo-notify

Open the graph (All Jobs / dashboard), run any demo job, and watch its
outgoing reference edges animate green while it runs.
""")
