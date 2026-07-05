defmodule CartographBackend.Dsl.ParserTest do
  use ExUnit.Case, async: true

  alias CartographBackend.Dsl.{Parser, TaskDsl, StepSpec}

  @full_dsl """
  processFiles {
      step "readDirectory" { path "data/inbox" },
      step "filter"        { extension "txt" },
      step "transform"     { operation "uppercase" },
      step "writeOutput"   { path "data/outbox" },
  }
  """

  test "parses task name and steps" do
    assert {:ok, %TaskDsl{task_name: "processFiles", steps: steps}} = Parser.parse(@full_dsl)
    assert length(steps) == 4

    assert %StepSpec{name: "readDirectory", params: %{"path" => "data/inbox"}} =
             Enum.at(steps, 0)

    assert %StepSpec{name: "transform", params: %{"operation" => "uppercase"}} =
             Enum.at(steps, 2)
  end

  test "supports steps without params" do
    dsl = """
    demo {
        step "readDirectory"
        step "filter" { extension "csv" },
    }
    """

    assert {:ok, %TaskDsl{steps: [first, second]}} = Parser.parse(dsl)
    assert first.params == %{}
    assert second.params == %{"extension" => "csv"}
  end

  test "supports line comments" do
    dsl = """
    myTask {
        // this step reads files
        step "readDirectory" { path "data/inbox" },
    }
    """

    assert {:ok, %TaskDsl{steps: [step]}} = Parser.parse(dsl)
    assert step.name == "readDirectory"
  end

  test "supports single-quoted strings" do
    dsl = "myTask { step 'readDirectory' { path 'data/inbox' }, }"
    assert {:ok, %TaskDsl{steps: [step]}} = Parser.parse(dsl)
    assert step.params["path"] == "data/inbox"
  end

  test "supports boolean param values" do
    dsl = "myTask { step \"doSomething\" { enabled true }, }"
    assert {:ok, %TaskDsl{steps: [step]}} = Parser.parse(dsl)
    assert step.params["enabled"] == true
  end

  test "supports integer param values" do
    dsl = "myTask { step \"doSomething\" { count 42 }, }"
    assert {:ok, %TaskDsl{steps: [step]}} = Parser.parse(dsl)
    assert step.params["count"] == 42
  end

  test "rejects empty DSL" do
    assert {:error, "DSL is empty"} = Parser.parse("")
    assert {:error, "DSL is empty"} = Parser.parse(nil)
    assert {:error, "DSL is empty"} = Parser.parse("   ")
  end

  test "rejects task with no steps" do
    assert {:error, _reason} = Parser.parse("emptyTask { }")
  end

  test "rejects invalid syntax" do
    assert {:error, _reason} = Parser.parse("this is not valid {{{")
  end

  test "rejects missing closing brace" do
    assert {:error, _reason} = Parser.parse("myTask { step \"foo\"")
  end

  # ── `use` keyword (additive alias of `job`) ───────────────────────────────────

  test "`use \"x\"` parses identically to `job \"x\"`" do
    {:ok, %TaskDsl{steps: [use_step]}} = Parser.parse("t { use \"x\" }")
    {:ok, %TaskDsl{steps: [job_step]}} = Parser.parse("t { job \"x\" }")

    assert use_step == %StepSpec{name: "__job__", params: %{"ref" => "x"}}
    assert use_step == job_step
  end

  test "`use` and `job` can be mixed in the same job" do
    dsl = """
    pipeline {
      use "alpha"
      job "beta"
      use "gamma"
    }
    """

    assert {:ok, %TaskDsl{steps: steps}} = Parser.parse(dsl)

    assert steps == [
             %StepSpec{name: "__job__", params: %{"ref" => "alpha"}},
             %StepSpec{name: "__job__", params: %{"ref" => "beta"}},
             %StepSpec{name: "__job__", params: %{"ref" => "gamma"}}
           ]
  end

  test "`use` accepts names with spaces and special chars" do
    assert {:ok, %TaskDsl{steps: [step]}} = Parser.parse("t { use \"teste #2\" }")
    assert step == %StepSpec{name: "__job__", params: %{"ref" => "teste #2"}}
  end

  test "`use` accepts single-quoted names" do
    assert {:ok, %TaskDsl{steps: [step]}} = Parser.parse("t { use 'teste #2' }")
    assert step == %StepSpec{name: "__job__", params: %{"ref" => "teste #2"}}
  end

  test "`useThing` is not mistaken for the `use` keyword" do
    # non_word lookahead: an identifier prefixed with `use` is not the keyword,
    # so this is a plain (and here invalid) token, not a job reference.
    assert {:error, _reason} = Parser.parse("t { useThing \"x\" }")
  end

  test "parses the user's example pipeline with `use` between steps" do
    dsl = """
    processFiles {
        step "readDirectory" { path "data/inbox" },
        step "filter"        { extension "txt" },
        use "teste #2",
        step "transform"     { operation "uppercase" },
        step "writeOutput"   { path "data/outbox" },
    }
    """

    assert {:ok, %TaskDsl{task_name: "processFiles", steps: steps}} = Parser.parse(dsl)
    assert length(steps) == 5

    assert %StepSpec{name: "readDirectory"} = Enum.at(steps, 0)
    assert %StepSpec{name: "filter"} = Enum.at(steps, 1)
    assert %StepSpec{name: "__job__", params: %{"ref" => "teste #2"}} = Enum.at(steps, 2)
    assert %StepSpec{name: "transform"} = Enum.at(steps, 3)
    assert %StepSpec{name: "writeOutput"} = Enum.at(steps, 4)
  end

  test "`use` works inside if/else branches" do
    dsl = """
    t {
      if state["go"] {
        use "branchJob"
      } else {
        job "fallbackJob"
      }
    }
    """

    assert {:ok, %TaskDsl{steps: [%{then_steps: then_steps, else_steps: else_steps}]}} =
             Parser.parse(dsl)

    assert then_steps == [%StepSpec{name: "__job__", params: %{"ref" => "branchJob"}}]
    assert else_steps == [%StepSpec{name: "__job__", params: %{"ref" => "fallbackJob"}}]
  end

  test "`use \"<code>\"` produces a binary ref carrying the job code" do
    assert {:ok, %TaskDsl{steps: [step]}} = Parser.parse(~s|c { use "backup-uI0IOQ45" }|)
    assert %StepSpec{name: "__job__", params: %{"ref" => "backup-uI0IOQ45"}} = step
  end

  test "`use \"<code>\"` coexists with steps and a trailing comma" do
    dsl = """
    caller {
      step "a"
      use "backup-uI0IOQ45",
      step "b"
    }
    """

    assert {:ok, %TaskDsl{steps: [a, ref, b]}} = Parser.parse(dsl)
    assert %StepSpec{name: "a"} = a
    assert %StepSpec{name: "__job__", params: %{"ref" => "backup-uI0IOQ45"}} = ref
    assert %StepSpec{name: "b"} = b
  end

  test "legacy `job \"name\"` still produces a binary ref" do
    assert {:ok, %TaskDsl{steps: [step]}} = Parser.parse(~s|c { job "legacyJob" }|)
    assert %StepSpec{name: "__job__", params: %{"ref" => "legacyJob"}} = step
  end
end
