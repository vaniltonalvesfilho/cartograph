defmodule CartographBackend.Dsl.Parser do
  @moduledoc """
  Parses the Cartograph task DSL into a %TaskDsl{} struct using NimbleParsec.

  Grammar:
    task      := IDENT '{' node+ '}'
    node      := step | job | use | if_node
    step      := 'step' value ('{' param* '}' ',')?
    job       := 'job' value           // alias of `use`; binary ref by job code
    use       := 'use' value           // value is the job code, e.g. "backup-uI0IOQ45"
    if_node   := 'if' condition '{' node+ '}' ('else' '{' node* '}')?
    condition := ['not'] cond_atom [compare_op cond_atom]
    cond_atom := state_get | value
    state_get := 'state' '[' STRING ']'
    compare_op := '==' | '!=' | '>=' | '<=' | '>' | '<'
    param     := IDENT value
    value     := STRING | BOOL | FLOAT | INT
  """

  import NimbleParsec

  alias CartographBackend.Dsl.{TaskDsl, StepSpec, IfNode}

  # ── Whitespace + // comments ─────────────────────────────────────────────────

  ws =
    choice([
      ascii_char([?\s, ?\t, ?\r, ?\n]),
      string("//") |> repeat(ascii_char(not: ?\n))
    ])
    |> repeat()
    |> ignore()

  # ── Identifier ───────────────────────────────────────────────────────────────

  ident_rest = repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))

  identifier =
    ascii_char([?a..?z, ?A..?Z, ?_])
    |> concat(ident_rest)
    |> reduce({List, :to_string, []})

  non_word = lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))

  # ── Strings ───────────────────────────────────────────────────────────────────

  escape =
    ignore(ascii_char([?\\]))
    |> choice([
      replace(ascii_char([?n]), ?\n),
      replace(ascii_char([?t]), ?\t),
      replace(ascii_char([?\\]), ?\\),
      replace(ascii_char([?"]), ?"),
      replace(ascii_char([?']), ?')
    ])

  dq_string =
    ignore(ascii_char([?"]))
    |> repeat(choice([escape, ascii_char(not: ?", not: ?\\)]))
    |> ignore(ascii_char([?"]))
    |> reduce({List, :to_string, []})

  sq_string =
    ignore(ascii_char([?']))
    |> repeat(choice([escape, ascii_char(not: ?', not: ?\\)]))
    |> ignore(ascii_char([?']))
    |> reduce({List, :to_string, []})

  # ── Boolean ───────────────────────────────────────────────────────────────────

  bool_val =
    choice([string("true"), string("false")])
    |> concat(non_word)
    |> post_traverse({__MODULE__, :to_bool, []})

  # ── Numbers ───────────────────────────────────────────────────────────────────

  sign = optional(string("-"))
  digits = ascii_string([?0..?9], min: 1)

  float_val =
    sign
    |> concat(digits)
    |> ignore(ascii_char([?.]))
    |> concat(digits)
    |> post_traverse({__MODULE__, :make_float, []})

  int_val =
    sign
    |> concat(digits)
    |> post_traverse({__MODULE__, :make_int, []})

  # ── Value (raw) ───────────────────────────────────────────────────────────────

  value = choice([dq_string, sq_string, bool_val, float_val, int_val])

  # ── Param ─────────────────────────────────────────────────────────────────────

  param =
    identifier
    |> concat(ws)
    |> concat(value)
    |> post_traverse({__MODULE__, :build_param, []})

  # Each param may be followed by an optional comma (for backward compat with
  # DSLs that write `key "v1", key2 "v2"` inside the block).
  params_block =
    ignore(ascii_char([?{]))
    |> concat(ws)
    |> repeat(
      param
      |> concat(ws)
      |> optional(ignore(ascii_char([?,])))
      |> concat(ws)
    )
    |> ignore(ascii_char([?}]))

  # ── Step ──────────────────────────────────────────────────────────────────────

  step_kw = ignore(string("step") |> concat(non_word))

  # Commas around the params block are fully optional — supports both the old
  # format `step "name", { params }` and the current `step "name" { params },`.
  step =
    step_kw
    |> concat(ws)
    |> concat(value)
    |> concat(ws)
    |> optional(ignore(ascii_char([?,])))
    |> concat(ws)
    |> optional(params_block)
    |> concat(ws)
    |> optional(ignore(ascii_char([?,])))
    |> post_traverse({__MODULE__, :build_step, []})

  # ── Job reference ─────────────────────────────────────────────────────────────

  job_kw = ignore(string("job") |> concat(non_word))

  # Optional trailing comma after a job/use reference, mirroring how `step`
  # swallows the comma that follows its params block. Additive: a reference
  # without a comma still parses, so existing `job "x"` DSLs are unaffected.
  optional_comma = optional(ws |> ignore(ascii_char([?,])))

  job_step =
    job_kw
    |> concat(ws)
    |> concat(value)
    |> concat(optional_comma)
    |> post_traverse({__MODULE__, :build_job_step, []})

  # `use "<code>"` — a quoted binary ref to another job by its public code
  # (e.g. `use "backup-uI0IOQ45"`). The expander resolves it globally by `code`,
  # authorizes the acting user, and inlines the referenced job's steps.
  #
  # `job "<code>"` is an alias kept for backward-compat; both reuse
  # build_job_step/5 and resolve identically.
  use_kw = ignore(string("use") |> concat(non_word))

  use_step =
    use_kw
    |> concat(ws)
    |> concat(value)
    |> concat(optional_comma)
    |> post_traverse({__MODULE__, :build_job_step, []})

  # ── Condition expression ──────────────────────────────────────────────────────
  #
  # condition := ['not'] cond_atom [compare_op cond_atom]
  #
  # cond_atom wraps raw values in {:literal, v} so we can distinguish them
  # from operator atoms (:eq, :gt, …) inside build_condition.

  state_get =
    ignore(string("state"))
    |> ignore(ws)
    |> ignore(ascii_char([?[]))
    |> ignore(ws)
    |> concat(choice([dq_string, sq_string]))
    |> ignore(ws)
    |> ignore(ascii_char([?]]))
    |> post_traverse({__MODULE__, :build_state_get, []})

  cond_atom =
    choice([
      state_get,
      value |> post_traverse({__MODULE__, :wrap_literal, []})
    ])

  compare_op =
    choice([
      string("==") |> replace(:eq),
      string("!=") |> replace(:neq),
      string(">=") |> replace(:gte),
      string("<=") |> replace(:lte),
      string(">") |> replace(:gt),
      string("<") |> replace(:lt)
    ])

  # :not_kw marker — kept in accumulator so build_condition can detect negation
  not_marker = string("not") |> concat(non_word) |> replace(:not_kw)

  condition =
    optional(not_marker |> concat(ws))
    |> concat(cond_atom)
    |> concat(ws)
    |> optional(compare_op |> concat(ws) |> concat(cond_atom))
    |> post_traverse({__MODULE__, :build_condition, []})

  # ── if/else node (mutual recursion via defparsec forward-ref) ─────────────────

  # node_list references parsec(:parsec_if_node) which is defined below.
  # NimbleParsec resolves parsec/1 calls at runtime so order doesn't matter.
  node_list =
    choice([job_step, use_step, step, parsec(:parsec_if_node)])
    |> concat(ws)
    |> repeat(
      choice([job_step, use_step, step, parsec(:parsec_if_node)])
      |> concat(ws)
    )

  # else_block: 'else' '{' node* '}'
  # wrap/1 collects the (possibly empty) node list into a single list item
  # so build_if_node can detect its presence via is_list/1.
  else_block =
    ws
    |> concat(ignore(string("else") |> concat(non_word)))
    |> concat(ws)
    |> ignore(ascii_char([?{]))
    |> concat(ws)
    |> wrap(optional(node_list))
    |> ignore(ascii_char([?}]))

  if_node =
    ignore(string("if") |> concat(non_word))
    |> concat(ws)
    |> concat(condition)
    |> concat(ws)
    |> ignore(ascii_char([?{]))
    |> concat(ws)
    |> concat(node_list)
    |> ignore(ascii_char([?}]))
    |> optional(else_block)
    |> post_traverse({__MODULE__, :build_if_node, []})

  defparsec(:parsec_if_node, if_node)

  # ── Task ──────────────────────────────────────────────────────────────────────

  task =
    identifier
    |> concat(ws)
    |> ignore(ascii_char([?{]))
    |> concat(ws)
    |> concat(node_list)
    |> ignore(ascii_char([?}]))
    |> concat(ws)
    |> eos()
    |> post_traverse({__MODULE__, :build_task, []})

  defparsec(:parsec_task, task)

  # ── Public API ────────────────────────────────────────────────────────────────

  @spec parse(String.t() | nil) :: {:ok, TaskDsl.t()} | {:error, String.t()}
  def parse(source) when source in [nil, ""], do: {:error, "DSL is empty"}

  def parse(source) when is_binary(source) do
    case String.trim(source) do
      "" ->
        {:error, "DSL is empty"}

      trimmed ->
        case parsec_task(trimmed) do
          {:ok, [%TaskDsl{} = result], "", _, _, _} ->
            {:ok, result}

          {:ok, _, rest, _, _, _} ->
            {:error, "Unexpected content: #{String.slice(rest, 0, 30)}"}

          {:error, reason, _rest, _, {line, _}, _} ->
            {:error, "Line #{line}: #{reason}"}
        end
    end
  end

  # ── Callbacks ─────────────────────────────────────────────────────────────────

  def to_bool(rest, ["false"], ctx, _, _), do: {rest, [false], ctx}
  def to_bool(rest, ["true"], ctx, _, _), do: {rest, [true], ctx}

  def make_int(rest, [digits], ctx, _, _), do: {rest, [String.to_integer(digits)], ctx}
  def make_int(rest, [digits, "-"], ctx, _, _), do: {rest, [-String.to_integer(digits)], ctx}

  def make_float(rest, [frac, int], ctx, _, _),
    do: {rest, [String.to_float("#{int}.#{frac}")], ctx}

  def make_float(rest, [frac, int, "-"], ctx, _, _),
    do: {rest, [-String.to_float("#{int}.#{frac}")], ctx}

  def build_param(rest, [value, key], ctx, _, _), do: {rest, [{key, value}], ctx}

  def build_job_step(rest, [ref], ctx, _, _) do
    {rest, [%StepSpec{name: "__job__", params: %{"ref" => ref}}], ctx}
  end

  def build_step(rest, args, ctx, _, _) do
    [name | params] = Enum.reverse(args)
    {rest, [%StepSpec{name: name, params: Map.new(params)}], ctx}
  end

  def build_task(rest, args, ctx, _, _) do
    [name | steps] = Enum.reverse(args)
    {rest, [%TaskDsl{task_name: name, steps: steps}], ctx}
  end

  def build_state_get(rest, [key], ctx, _, _), do: {rest, [{:state_get, key}], ctx}

  def wrap_literal(rest, [v], ctx, _, _), do: {rest, [{:literal, v}], ctx}

  # condition args (reversed parse order):
  #   [atom]                     → bare truthiness
  #   [:not_kw, atom]            → negation
  #   [right, op, left]          → comparison
  #   [right, op, left, :not_kw] → negated comparison
  def build_condition(rest, args, ctx, _, _) do
    expr =
      case Enum.reverse(args) do
        [:not_kw, atom] -> {:logical, :not, atom}
        [:not_kw, left, op, right] -> {:logical, :not, {:compare, op, left, right}}
        [left, op, right] -> {:compare, op, left, right}
        [atom] -> atom
      end

    {rest, [expr], ctx}
  end

  # if_node args (reversed): last item is either a list (else block via wrap)
  # or a node/condition (no else). First item after reverse is the condition.
  def build_if_node(rest, args, ctx, _, _) do
    items = Enum.reverse(args)
    [condition | body] = items

    {then_steps, else_steps} =
      case List.last(body) do
        else_nodes when is_list(else_nodes) -> {Enum.drop(body, -1), else_nodes}
        _ -> {body, []}
      end

    {rest, [%IfNode{condition: condition, then_steps: then_steps, else_steps: else_steps}], ctx}
  end
end
