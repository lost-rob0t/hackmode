% Durable knowledge: operation MCP surface + canonical tool-run wire contract.
% Verified 2026-11-24 in worktree branch mcp/operation-tools (commits
% 1dfbcc1/fa8511d/5d14261/ed8edf7 on base 07425b3); all suites green,
% prolog-verify PASS, boundary denylist clean.

mcp_system(hackmode_mcp, 'source/hackmode-mcp').
mcp_gate(test_gate,
         'asdf:test-system :hackmode-mcp (core.yml); suite prints "Hackmode MCP tests passed."').
mcp_gate(local_gate,
         'local gate /tmp/opencode/hm-mcp-gate.sh (ephemeral — rebuild from KB): CL_SOURCE_REGISTRY=/tmp/opencode/star-lang-pin// (recursive), LD_LIBRARY_PATH=nix lmdb+openssl store libs, ql:*local-project-directories* nil, load-asd hackmode/hackmode-database/hackmode-starlang/hackmode-mcp (+tests), test-system each; ~5 s warm, minutes cold').
mcp_design_doc(hackmode_mcp, 'docs/architecture/operation-mcp-tools.org (ADADR record, slices, open questions)').
mcp_design_doc(templates_overhaul, 'docs/architecture/operation-templates.org (bbp/op/htb set, consumption contracts, install gap)').

% Architecture invariants (mirror AGENTS.md / ADR #149):
mcp_rule(thin_client,
         'the MCP server owns no durable state and adds no mutation path; it calls canonical operation/provider/asset/outbox APIs only — no second operation model (EPIC #150)').
mcp_rule(catalog_derivation,
         'run-tool input schemas are derived at load from the pentest IR (declarations carry :fields with camelCase :name/:type/:required); adding a tool to pentest.star extends the catalog with no hand-written schema table').
mcp_rule(error_taxonomy,
         'protocol errors are JSON-RPC errors (-32601 unknown method, -32602 unknown tool/bad params, -32700 parse, -32600 non-object); tool execution errors are results with isError true carrying the complete condition text').
mcp_rule(lossless_results,
         'results carry exact finding evidence and complete job error text; asset_query never filters by default and reports truncated:true when an explicit limit slices; no redaction/truncation anywhere (regression ledger)').
mcp_rule(fail_closed_scope,
         'run tools and asset_query require an open operation store (*db*) and fail closed otherwise — operation scoping is the access boundary, enforced by scope not by evidence mutation').
mcp_rule(protocol_policy,
         'supported protocol versions {2024-11-05, 2025-06-18}, echo-back at initialize, else answer 2025-06-18; stdio newline-delimited JSON-RPC; stdout protocol-only, stderr logs; EOF exits 0 (spec transports pages re-pinned 2026-11-24)').
mcp_rule(sync_slice1,
         'slice-1 run tools are synchronous (one call at a time, no retries of effectful calls = documented rate-limit posture); async dispatch via dispatch-capability futures is slice 2, daemon binding on #151 control protocol is slice 3').
mcp_rule(tool_identity,
         'OPERATOR DIRECTIVE 2026-11-24: one Star-Lang-declared tool defines exactly one MCP tool, named verbatim (subfinder/crtsh/massdns/nmap/httpx/katana/nuclei/zap); no enum-dispatch meta-tools; composed convenience tools are allowed only as future additions on top and never replace or hide a per-tool surface').

% tool-run wire contract (verified against the pinned star-lang 7db8998):
tool_run_wire_contract(tool_run,
    'spec must DECLARE canonical metadata (id/dataset/dtype/schemaVersion required, dateAdded/dateUpdated required, document-id + unix-time scalars) or encoded documents lose it: prototype/relation-compatibility.lisp compatible-create-document strips generated *runtime-metadata-fields* (id dataset dtype schemaVersion createdAt dateAdded updatedAt dateUpdated) unless the contract declares the field or the caller supplied it').
tool_run_wire_contract(id_policy,
    ':id-policy (:kind digest :algorithm sha256 :fields (runId)) on tool-run gives deterministic document identity per run; byte-identical re-enqueues collapse into one outbox record (outbox id = digest(document-id, payload digest))').
tool_run_wire_contract(outbox_minimum,
    'enqueue-starintel-json/make-outbox-entry-for-json require _id AND dtype in the payload JSON; missing either -> "Cannot enqueue StarIntel document without a canonical _id."').
tool_run_wire_contract(map_keys_verbatim,
    'star-lang map values keep their keys verbatim through normalization: keyword keys leak into the wire document, use string-keyed alists for :raw maps').
tool_run_wire_contract(jsown_obj_tag,
    'encode-document returns a plain alist; jsown serializes plain lists as JSON arrays — tag documents (and nested maps) with (cons :obj alist) before to-json or the payload becomes an array').

% jsown quicklisp-dist facts (pinned by probes 2026-11-24):
cl_json_rule(jsown_dist,
    'dist jsown: parse returns NIL on undecodable input (no signal) and drops null values ("id"); booleans/null are :true/:false/:null; (:OBJ ("k" . v) ...) lists are objects, everything else arrays').
cl_json_rule(two_jsown_copies,
    'two jsown versions exist on this host (~/common-lisp local-projects vs quicklisp dist 2020-02-18): always probe with ql:*local-project-directories* nil or results mislead').

% CL toolchain traps hit this cycle:
cl_trap(ecase_strings,
        'ecase on strings falls through (eql, not string=): IR :type dispatch must use cond/string=').
cl_trap(getenv_nil,
        'SBCL (setf uiop:getenv) rejects NIL — write "" to clear; this UIOP has no uiop:setenv export').
cl_trap(archive_mtime_fasl_cache,
        'git-archive exported pins carry old commit mtimes: if a pin is refreshed in place, ASDF fasl cache keeps loading the stale fasl (source older than fasl) — touch pin sources to force recompile. (Cost one debugging cycle on 2026-11-24; the metadata mystery was the compat layer, not the cache.)').
