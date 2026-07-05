# JSON error contract (validation 422 + map)

**Status:** Current · **Updated:** 2026-07-04

## Overview

The controllers used to respond with errors inconsistently: some returned
`%{error: "text"}`, others `%{errors: %{field => [msgs]}}`; validation sometimes
came out as 400, sometimes as 422; and the changeset serialization was duplicated
across 8 controllers, in 3 variants — one of which dropped placeholder
interpolation (`%{count}` leaked to the client). The frontend, in turn, had
different readers for each format. The design below standardizes a single
contract.

## Design

A single contract, centralized in `CartographBackendWeb.ErrorHelpers`
(imported in `use ..., :controller`):

- **Validation errors (changeset):** status **422** with a per-field map —
  `%{errors: %{"field" => ["message"]}}` — via `unprocessable/2`. The changeset
  conversion (`changeset_messages/1`) **preserves interpolation**.
- **Other errors:** flat message `%{error: "..."}` with the appropriate status —
  `forbidden/1` (403), `bad_request/1` (400), 404, etc.
- **Admin-only:** `require_admin/1` (`:ok | {:error, conn}` with a rendered 403).
- On the **frontend**, a single helper `extractApiError(err, fallback)`
  (`utils/http-error.util.ts`) understands both formats (validation map and flat
  message) and is used by every form.

## Trade-offs

- A client knows: 422 ⇒ field errors (map); 4xx with `error` ⇒ single message.
- The changeset serialization exists in one place; adding a new field does not
  require touching 8 controllers.

## Open questions / future evolution

- Changing the error format is a contract change — it should be treated as a break
  and communicated to API consumers before it lands.
