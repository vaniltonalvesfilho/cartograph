# Design docs

Cartograph design docs: they describe **how each subsystem works today** and why —
in the format **overview → design → trade-offs → open questions**. Unlike an ADR, a
design doc is **living**: when the subsystem changes, the document is updated (and
the "Updated" date follows) instead of becoming an immutable record.

| Document | Topic |
|----------|-------|
| [API surfaces](api-surfaces.md) | REST and GraphQL coexisting; shared authorization |
| [Authorization](authorization.md) | Integer levels with cascade down the hierarchy |
| [JSON error contract](error-contract.md) | Validation 422 + per-field map |
| [DSL execution engine](dsl-execution-engine.md) | Parser → resolution → execution → status |
