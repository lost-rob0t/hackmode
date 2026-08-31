# Repository agent boundary

Development-agent framework implementation and terminology are isolated to `agent-zero/**`.

Before editing this repository, read:

- `agent-zero/README.md`
- `agent-zero/forbidden-outside-agent-zero.txt`

Every non-comment token listed in `agent-zero/forbidden-outside-agent-zero.txt` is forbidden, case-insensitively, in **all tracked paths and tracked file content outside `agent-zero/**`**.

This includes source code, symbols, comments, strings, tests, fixtures, snapshots, filenames, directory names, product README text, architecture/design/migration documents, examples, templates, tools, Emacs code, Prolog, shell/configuration files, and `.github/**` workflows.

There is no explanatory-text exception. Outside `agent-zero/**`, use only Hackmode-native product terminology. Do not create product abstractions for development-worker identity, scheduling, lane ownership, task selection, worker scope/authorization, coordination, or lifecycle.

Before committing and before opening/updating a PR, ensure the repository boundary workflow passes. A failure is a correctness failure: remove or rephrase the leakage. Never weaken the denylist check, add product-tree exceptions, or broaden exclusions to make a change pass.

# Non-negotiable product invariants

Agents must preserve operator-approved behavior and data semantics. Do not silently narrow a capability, destroy information, or invent a protective policy that the repository/operator did not request.

For operation-scoped traffic capture and evidence, **lossless capture is the default invariant**:

- Do not introduce redaction, sanitization, secret stripping, value replacement, hashing in place of retained originals, silent truncation, omission, or lossy normalization of captured HTTP or other protocol evidence unless the operator explicitly requests that exact behavior.
- Authorization headers, cookies, bearer values, API-key-shaped fields, session identifiers, query values, form values, and response fields are evidence. Preserve the exact observed value in canonical raw evidence.
- A bounded graph/KB/model projection may carry an evidence reference instead of copying large values everywhere, but the exact source evidence must remain retrievable. A reference is not permission to destroy or mutate the source.
- Storage limits or truncation, when explicitly configured, must be visible in the record and provenance. Never silently pretend a partial record is complete.
- Promotion/export scope is separate from capture fidelity. Keeping evidence operation-scoped is allowed; mutating the evidence to enforce scope is not.
- Do not invent privacy, compliance, safety, or convenience policy as a reason to remove data or neuter an operator-approved capability. If a new policy is genuinely required, make it explicit and get operator approval instead of smuggling it into implementation/design defaults.

Similar regression classes are also banned:

- replacing canonical data with summaries/digests when exact data was requested or required;
- silently changing an authoritative store into a lossy projection;
- adding default filters that make captured/ingested evidence disappear;
- treating a transport send/publish as proof of persistence or acceptance;
- declaring work complete while the requested behavior exists only in prose, a stub, or a placeholder;
- weakening an explicit operator requirement because an agent considers a different default more prudent.

# Agent-caused regression ledger

When the operator identifies an agent-caused regression, bad assumption, or unacceptable behavior, the agent handling the correction must do all of the following in the same change:

1. Fix the actual code/design/configuration that caused the problem.
2. Add or refine a concrete invariant in this file so the same class of mistake is forbidden.
3. Add an automated regression check when the invariant is reasonably machine-checkable; otherwise make the acceptance proof explicit in the relevant design/test plan.
4. Record the regression below with the failure and the prevention rule.
5. Never delete, weaken, or route around a regression rule merely to make a later change pass.

## 2026-08-31 — IPX HTTP evidence redaction

Regression: the IPX HTTP design introduced redacted headers, canonical stripping of authorization/cookie/API-key fields before expert/StarIntel projection, and an acceptance criterion requiring secret-bearing fields to be absent. That made passive evidence lossy and would have prevented later authorized analysis from recovering the exact observed traffic.

Prevention rule: operation-scoped capture evidence is lossless by default. Exact captured values remain canonical raw evidence; projections may reference them for boundedness but may not silently redact, sanitize, hash-away, omit, or mutate them. Scope/promotion policy must be enforced by access and export boundaries rather than destruction of source evidence.
