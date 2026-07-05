# DSL execution engine

**Status:** Current · **Updated:** 2026-07-04

## Overview

A job is defined in a custom DSL (see the README and the in-app docs page).
The text needs to become something executable, and the same definition also needs
to be **visualized** (the flow of steps, `if/else` branches, and referenced
sub-jobs). On top of that, execution happens asynchronously and needs to survive
restarts.

## Design

A layered pipeline, each layer with a single responsibility:

1. **Parser** (`Dsl.Parser`, NimbleParsec) → typed AST: `StepSpec` (one step),
   `IfNode` (a branch), and the reference meta-step (`use`/`job`).
2. **Reference resolution** (`Dsl.RefResolver`): given a job's public `code`, it
   resolves the `TaskDefinition` **with `:view` authorization** (bypassed for
   `:system`). A nonexistent job and a forbidden job return the **same** generic
   error (no enumeration oracle). This is the point shared by:
   - **`Dsl.Expander`** — flattens the references in a job's steps for **execution**
     (with cycle detection, depth limit, and step-count limit);
   - **`Dsl.Flow`** — keeps the tree structure for **visualization** (each
     reference becomes a `job` node with its nested steps; broken refs become
     `job_error` nodes without failing the rest).
3. **Execution** (`Engine.ExecutorWorker`, Oban): walks the expanded AST,
   evaluating conditions (`Dsl.Condition`) against the shared state and creating
   `StepExecution` records *just-in-time* only for the chosen branch.
4. **Status** as canonical strings in `Executions.Status`
   (`PENDING/RUNNING/SUCCESS/FAILED/STOPPED/SKIPPED`) with `active?/terminal?`
   predicates — no literals scattered around.

Oban (a PostgreSQL-backed queue) guarantees durability and no duplication across
nodes.

## Trade-offs

- Execution and visualization start from the **same** definition, with the same
  resolution/access rule — the flow screen does not lie about what would run.

## Open questions / future evolution

- The `ExecutorWorker` currently concentrates a lot (walking the tree, persisting
  via `Repo` directly, streaming logs). A future decomposition into
  `Executions.*` + an `Engine.Interpreter` is mapped as debt — when done, this
  document should be updated.
