# API surfaces — REST and GraphQL

**Status:** Current · **Updated:** 2026-07-04

## Overview

The API exposes the same entities (groups, projects, jobs, executions) through
two surfaces: a REST API at `/api/*` and a GraphQL API at `/graphql` (with
subscriptions over WebSocket). REST came first; GraphQL was added later. Today the
frontend uses **mostly REST** (the majority of components) and **GraphQL in
specific spots**: dashboard metrics (`dashboardMetrics`) and live execution
logs/status (the `executionLog`/`executionStatus` subscriptions).

Keeping both surfaces creates a risk of divergence — the "who may
create/move/run" rules were at one point implemented in parallel in the REST
controllers and the GraphQL resolvers. The design below removes that duplication.

## Design

- **Both** surfaces coexist. REST is the primary path; GraphQL covers the cases
  where aggregation/subscriptions pay off more (dashboard, real time).
- **The authorization rule lives in a single place** — the
  `CartographBackend.Authorization` context (see [Authorization](authorization.md)).
  REST calls the context directly; GraphQL goes through the
  `CartographBackendWeb.Graphql.Authz` adapter, whose only extra responsibility is
  to convert the error format (`{:error, :forbidden}` → `{:error, "forbidden"}`).
- No business logic lives in the resolvers/controllers without also being in the
  domain context.

## Trade-offs

- A change to the access policy is made once, in the context, and applies to both
  APIs.
- The cost is maintaining two *kinds* of contract (REST with integer ids/camelCase;
  GraphQL with string `ID` and nullable fields). On the frontend this shows up as
  separate types (`models.ts` for REST, `graphql/types.ts` for GraphQL).

## Open questions / future evolution

- As long as GraphQL is used in only 2 screens, the ROI of expanding its use is
  low; the decision to retire one of the surfaces remains open for the future.
