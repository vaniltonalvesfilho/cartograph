# Level-based authorization with cascade down the hierarchy

**Status:** Current · **Updated:** 2026-07-04

## Overview

Resources form a hierarchy: groups → subgroups → projects → jobs. A user may be
granted access at any level of that tree, and that access needs to "flow down" to
the descendants (whoever administers a group administers its projects and jobs)
without requiring an explicit grant on every leaf.

## Design

Access is modeled as **a single integer per (user, resource)**:

| Level | Value | Can |
|-------|-------|-----|
| Wayfarer | 10 | view |
| Scout | 20 | run |
| Explorer | 30 | create/edit |
| Navigator | 40 | manage members / delete |
| Cartographer | 50 | full control (global admin) |

- **Cascade downward:** the effective level on a resource is the **maximum** of the
  direct grant on it and the grant inherited from its ancestors.
- Each action requires a minimum level (`@required_level`); `is_admin` is
  equivalent to 50 on any resource.
- The level definition is a **single source** (`@levels` in `Authorization`),
  exposed to the frontend via `GET /api/access-levels`.
- The **policies** (`authorize_create_*`, `authorize_move_*`, `authorize_execution`)
  live in the `Authorization` context and are shared by REST and GraphQL
  (see [API surfaces](api-surfaces.md)).
- The ancestry traversal is **pure and shared** (`group_chain/3`) between
  `effective_level/2` (a single resource) and `scope/1` (bulk visibility), loading
  memberships + the parent map once instead of one query per level.

## Trade-offs

- Authorization becomes an integer comparison: cheap and easy to reason about.
- Anti-lockout and auto-owner are handled separately (whoever creates becomes the
  owner; the last admin cannot be removed).

## Open questions / future evolution

- One known limit: `effective_level` loads all groups (id+parent) per call; for
  very large hierarchies a `WITH RECURSIVE` would load only the ancestors — an
  optimization left for when the scale justifies it.
