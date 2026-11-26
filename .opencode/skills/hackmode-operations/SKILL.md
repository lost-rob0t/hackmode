---
name: hackmode-operations
description: Operate Hackmode operations (create, select, inspect) through the canonical MCP surface — op_list, op_create, op_use, op_status; run this skill before any recon run, asset query, or operation-scoped work
---

# hackmode-operations — the operation model

An operation is the unit of work: a workspace directory (default
`~/hackmode/<name>`) plus a Tek9 store at `<workspace>/.hackmode/`. All
typed state — assets, jobs, findings, evidence — lives in that store. The
runtime (and the MCP server on top of it) is the only authority.

## Fixed MCP tools

| MCP tool   | args                        | notes                                                            |
|------------+-----------------------------+------------------------------------------------------------------|
| op_list    | —                           | persisted operations + current selection                         |
| op_create  | `name` (req), `description`, `path` | default root `~/hackmode/<name>` / `$HACKMODE_OPERATIONS_DIR`; persists the registry record and creates the workspace dir; template seeding is separate (see hackmode-templates) |
| op_use     | `name` (req)                | selects the operation and opens its store                        |
| op_status  | —                           | current operation detail, or null when none is selected          |

## Ordering that does not bend

1. `op_list` to see what exists; `op_create` only for genuinely new work.
2. `op_use` before any run tool or `asset_query` — run tools and asset
   queries are scoped to the open operation store and FAIL CLOSED with
   none open. There is no implicit default operation.
3. One current operation per hm-mcp process; the stdio loop is
   sequential, so selection cannot race within one client.

## Authority boundaries

- Clients never keep parallel operation state and never touch the Tek9
  store directly. No second registry, second operation DB, second graph
  store, or second KB authority — this includes "just a JSON cache".
- The MCP server exposes only canonical APIs: no direct store access, no
  expert write path (the expert layer stays passive over operation
  state), and it never talks to StarIntel ingest on its own.
- Operation scoping is the access boundary on evidence: scope by
  selection (`op_use`), never by mutating or filtering evidence.

## Lossless evidence invariant

Operation-scoped capture and evidence are lossless by default:

- No redaction, sanitization, secret stripping, hashing-in-place, silent
  truncation, or omission of captured values — authorization headers,
  cookies, session ids, API-key-shaped fields are evidence.
- A bounded view may reference evidence instead of copying it, but the
  exact source stays retrievable.
- Storage limits, when explicitly configured, must be visible in the
  record; never present a partial record as complete.
- Do not invent privacy/compliance/convenience policy as a reason to
  drop data. If a policy is genuinely required, get operator approval
  first.
