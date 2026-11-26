---
name: hackmode-recon
description: Run recon and vulnerability scanning through Hackmode's canonical provider path — discover tools at runtime with capability_list and tools/list, then call one tool per run; run this skill before executing any scan or reading scan results
---

# hackmode-recon — declared tools over the canonical provider path

The pentest tool catalog is declared in Star-Lang
(`source/hackmode-starlang/spec/pentest.star`) and the MCP server derives
its catalog from that declaration at load. One declared Hackmode tool is
exactly one MCP tool, named verbatim. The catalog on the wire is the only
truth — never memorize tool lists or capabilities from memory or prose.

## Discover before you run

1. `tools/list` (or ask the client) — the full callable surface with
   per-tool input schemas, derived from the declaration.
2. `capability_list` — registered capability providers plus the declared
   catalog with backend readiness for each tool. It tells you what can
   run in THIS process, right now.

Before every engagement pass, re-check `capability_list`. Readiness is
runtime state: what was unavailable earlier may be registered now, and
what this document says is background, not authority.

## Calling a run tool

- `op_use` first — run tools are scoped to the open operation store and
  fail closed with none open (see hackmode-operations).
- One MCP tool call runs exactly that one tool against `target` through
  the canonical provider path: typed input asset → provider → persisted
  findings → tool-run document in the outbox.
- Input schemas come from the declaration (`tools/list`): `target` is
  required, `runId` is optional (caller-supplied ids are honored, so
  operator reproducibility wins; otherwise the server generates one),
  plus declared options. Read the schema instead of guessing argument
  names.
- Execution is synchronous: the call returns when the job is persisted.

## When a tool is not ready

A declared tool without a registered backend still appears in
`tools/list`; calling it returns a clean `isError` result saying so.
Correct response: report to the operator which tool is unavailable and
stop. Wrong responses: retrying, faking results, or shelling out to a
local binary as a bypass — undeclared runs create no operation assets and
no tool-run documents, which silently breaks the evidence trail.

## Reading results

- `structuredContent` carries the encoded tool-run document plus `job`:
  id, capability, provider, state, createdCount, projected assets, and
  the error text when failed. Read the document; do not reconstruct
  status from partial fields.
- On failure the job error embeds COMPLETE stdout+stderr. Never truncate
  it when relaying; summarize in your own words and keep the full record
  in the operation store.
- `asset_query` lists persisted typed assets: optional `type` filter and
  an EXPLICIT positive `limit` (the response then reports `truncated:
  true` with the full match count). There is no default filtering.
- Bounded consumption is your job as the client: query with explicit
  filters/limits instead of asking the server to drop evidence.

## Scope discipline

- Authorized targets only — the operation's scope table and
  `.config/blacklist.txt` are the operator's word; respect both (see
  hackmode-bbp).
- Results persist in the operation store even if your session dies;
  re-query assets instead of re-running scans to "remember".
