defmodule CartographBackend.Dsl.IfElseTest do
  use ExUnit.Case, async: true

  alias CartographBackend.Dsl.{Parser, TaskDsl, StepSpec, IfNode, Condition}

  # ── Parser: if without else ───────────────────────────────────────────────────

  test "parses if without else" do
    dsl = """
    myTask {
      step "before"
      if state["count"] > 0 {
        step "transform"
      }
      step "after"
    }
    """

    assert {:ok, %TaskDsl{steps: [before, %IfNode{} = if_node, after_step]}} = Parser.parse(dsl)
    assert before.name == "before"
    assert after_step.name == "after"
    assert if_node.condition == {:compare, :gt, {:state_get, "count"}, {:literal, 0}}
    assert [%StepSpec{name: "transform"}] = if_node.then_steps
    assert if_node.else_steps == []
  end

  # ── Parser: if with else ──────────────────────────────────────────────────────

  test "parses if with else" do
    dsl = """
    myTask {
      if state["status"] == "ok" {
        step "transform"
      } else {
        step "log"
      }
    }
    """

    assert {:ok, %TaskDsl{steps: [%IfNode{} = node]}} = Parser.parse(dsl)
    assert node.condition == {:compare, :eq, {:state_get, "status"}, {:literal, "ok"}}
    assert [%StepSpec{name: "transform"}] = node.then_steps
    assert [%StepSpec{name: "log"}] = node.else_steps
  end

  # ── Parser: not condition ─────────────────────────────────────────────────────

  test "parses 'not' condition" do
    dsl = """
    myTask {
      if not state["failed"] {
        step "writeOutput"
      }
    }
    """

    assert {:ok, %TaskDsl{steps: [%IfNode{} = node]}} = Parser.parse(dsl)
    assert node.condition == {:logical, :not, {:state_get, "failed"}}
  end

  # ── Parser: all comparison operators ─────────────────────────────────────────

  test "parses all comparison operators" do
    for {op_str, op_atom} <- [
          {"==", :eq},
          {"!=", :neq},
          {">", :gt},
          {"<", :lt},
          {">=", :gte},
          {"<=", :lte}
        ] do
      dsl = "t { if state[\"x\"] #{op_str} 1 { step \"s\" } }"

      assert {:ok, %TaskDsl{steps: [%IfNode{condition: {:compare, ^op_atom, _, _}}]}} =
               Parser.parse(dsl)
    end
  end

  # ── Parser: bare truthiness ───────────────────────────────────────────────────

  test "parses bare state truthiness check" do
    dsl = "t { if state[\"done\"] { step \"s\" } }"
    assert {:ok, %TaskDsl{steps: [%IfNode{condition: {:state_get, "done"}}]}} = Parser.parse(dsl)
  end

  # ── Parser: literal condition ─────────────────────────────────────────────────

  test "parses literal true/false condition" do
    dsl = "t { if true { step \"s\" } }"
    assert {:ok, %TaskDsl{steps: [%IfNode{condition: {:literal, true}}]}} = Parser.parse(dsl)
  end

  # ── Parser: nested if ─────────────────────────────────────────────────────────

  test "parses nested if inside then-branch" do
    dsl = """
    t {
      if state["a"] > 0 {
        if state["b"] == "ok" {
          step "inner"
        }
      }
    }
    """

    assert {:ok, %TaskDsl{steps: [%IfNode{then_steps: [%IfNode{} = inner]}]}} = Parser.parse(dsl)
    assert inner.condition == {:compare, :eq, {:state_get, "b"}, {:literal, "ok"}}
  end

  # ── Parser: multiple steps in each branch ─────────────────────────────────────

  test "parses multiple steps in then and else" do
    dsl = """
    t {
      if state["x"] > 0 {
        step "a"
        step "b"
        step "c"
      } else {
        step "d"
        step "e"
      }
    }
    """

    assert {:ok, %TaskDsl{steps: [%IfNode{then_steps: then, else_steps: els}]}} =
             Parser.parse(dsl)

    assert length(then) == 3
    assert length(els) == 2
  end

  # ── Condition evaluator ───────────────────────────────────────────────────────

  test "eval: literal" do
    assert Condition.eval({:literal, true}, %{}) == true
    assert Condition.eval({:literal, false}, %{}) == false
    assert Condition.eval({:literal, 42}, %{}) == 42
  end

  test "eval: state_get" do
    assert Condition.eval({:state_get, "x"}, %{"x" => 5}) == 5
    assert Condition.eval({:state_get, "x"}, %{"x" => nil}) == nil
    assert Condition.eval({:state_get, "missing"}, %{}) == nil
  end

  test "eval: comparisons" do
    state = %{"count" => 3, "name" => "bob"}

    assert Condition.eval({:compare, :eq, {:state_get, "count"}, {:literal, 3}}, state) == true
    assert Condition.eval({:compare, :neq, {:state_get, "count"}, {:literal, 3}}, state) == false
    assert Condition.eval({:compare, :gt, {:state_get, "count"}, {:literal, 2}}, state) == true
    assert Condition.eval({:compare, :lt, {:state_get, "count"}, {:literal, 2}}, state) == false
    assert Condition.eval({:compare, :gte, {:state_get, "count"}, {:literal, 3}}, state) == true
    assert Condition.eval({:compare, :lte, {:state_get, "count"}, {:literal, 3}}, state) == true
    assert Condition.eval({:compare, :eq, {:state_get, "name"}, {:literal, "bob"}}, state) == true
  end

  test "eval: logical not" do
    assert Condition.eval({:logical, :not, {:literal, true}}, %{}) == false
    assert Condition.eval({:logical, :not, {:literal, false}}, %{}) == true
    assert Condition.eval({:logical, :not, {:literal, nil}}, %{}) == true
  end

  test "eval: logical and" do
    assert Condition.eval({:logical, :and, [{:literal, true}, {:literal, true}]}, %{}) == true
    assert Condition.eval({:logical, :and, [{:literal, true}, {:literal, false}]}, %{}) == false
    assert Condition.eval({:logical, :and, [{:literal, false}, {:literal, true}]}, %{}) == false
  end

  test "eval: logical or" do
    assert Condition.eval({:logical, :or, [{:literal, true}, {:literal, false}]}, %{}) == true
    assert Condition.eval({:logical, :or, [{:literal, false}, {:literal, false}]}, %{}) == false
  end

  # ── Round-trip: parse + eval ──────────────────────────────────────────────────

  test "parsed condition evaluates correctly against state" do
    dsl = "t { if state[\"count\"] > 0 { step \"s\" } }"
    {:ok, %TaskDsl{steps: [%IfNode{condition: cond_expr}]}} = Parser.parse(dsl)

    assert Condition.eval(cond_expr, %{"count" => 5}) == true
    assert Condition.eval(cond_expr, %{"count" => 0}) == false
    assert Condition.eval(cond_expr, %{"count" => -1}) == false
  end
end
