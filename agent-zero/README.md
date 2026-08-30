# Hackmode Auto-RAGE workers

The autonomous development-worker home is Hackmode's `agent-zero/` tree, not the Hackmode product runtime and not StarIntel Auto-Research.

## Absolute boundary

**All RAGE / Auto-RAGE implementation and terminology belongs under `agent-zero/**`.**

RAGE is development-agent orchestration. It is not a Common Lisp Hackmode subsystem, product API, runtime state model, scheduler, authorization layer, task vocabulary, persistence model, architecture concept, or product-documentation term.

Outside `agent-zero/**`, the repository must contain **zero RAGE references**. This applies case-insensitively to:

- file and directory names;
- Common Lisp symbols, package exports, classes, structs, functions, variables, conditions, strings, and comments;
- Emacs Lisp, shell, Prolog, JavaScript, configuration, fixtures, and generated source checked into Git;
- tests, test names, test descriptions, snapshots, and sample data;
- product README text and architecture/design/migration documentation;
- `.github/**` workflow names, job names, comments, scripts, and hard-coded lane names;
- `tools/**`, `templates/**`, and every other tracked product-facing path.

There are no product-tree exceptions for explanatory text. If product code or documentation needs to describe a concept implemented by one of these workers, describe the **Hackmode-native concept** only. Do not mention the worker framework, even to say that it must not be used there.

`forbidden-outside-agent-zero.txt` is the machine-readable lexical denylist. Repository CI reads it and fails if any listed token occurs in either a tracked path or tracked file content outside `agent-zero/**`.

Historical Git commits may retain old mistakes; do not rewrite history merely to scrub them. The checked-out tree and all new changes must obey the boundary.

## Mandatory worker prompt rule

Every Agent Zero worker operating from this tree must enforce the following before editing and again before opening/updating a PR:

1. Never create, modify, or retain a path outside `agent-zero/**` whose name contains a denylisted token.
2. Never create, modify, or retain content outside `agent-zero/**` containing a denylisted token, including comments, docs, strings, symbols, fixtures, tests, or examples.
3. Never create a product abstraction for worker identity, scheduling, lane ownership, task selection, worker authorization, worker scope, or worker lifecycle.
4. Implement assigned work exclusively in Hackmode-native terms: operations, assets, providers, expert modes, typed actions, graph records/deltas, evidence, KB entries, plans/playbooks, persistence, replay, promotion, and other actual product concepts.
5. If a requested product change appears to require a denylisted term, re-model/rephrase it in product-native language. Do not add an exception.
6. Treat any boundary-CI failure as a correctness failure. Remove the leakage rather than weakening, bypassing, or excluding the check.

## Rollback marker

The known-good rollback point immediately before the first Auto-RAGE migration attempt is `dca7592da8a684696556a89cefe782ee19dddfcc`.

The historical migration commit `c64ae3f244c200a0e6fceaa28a9ebff1a8dfbdb4` is **not** a clean rollback point: it incorrectly introduced RAGE worker policy into the Common Lisp product runtime. Never restore that runtime design.

If autonomous worker changes become tangled, branch/worktree from the known-good rollback point and compare/reconcile forward. Do not rewrite `master` to recover.

## Worker ownership

Two initial Agent Zero profiles intentionally have disjoint ownership:

- `hackmode-rage-database` — Hackmode database, execution graph, operational/long-term KB persistence, promotion/export plumbing, and persistence tests.
- `hackmode-rage-hackpert` — Hackpert expert engine, passive/active orchestration, Prolog rules/interfaces, plans/playbooks, provider-action integration, and LISH expert controls.

Use separate worktrees/branches and separate worker/run identities. A worker must inspect current open Hackmode PRs before claiming work. It must not edit the other worker's owned implementation area merely to unblock itself; define or request a typed boundary and hand the dependency across instead.

`pr-lanes.txt` is the Agent Zero-owned branch-prefix configuration used by the repository's generic PR serialization workflow. Keep RAGE-specific lane names/configuration here rather than hard-coding them into `.github` workflow logic.

## StarIntel boundary

These are **Hackmode workers**. They must not discover or implement ordinary StarIntel product issues.

StarIntel may be touched only when the active Hackmode operation/issue is explicitly cyber/BBP related, for example source-assisted security review, attack-surface/recon work, authorized security testing, validating a Hackmode security integration, or projecting security findings/evidence through canonical StarIntel APIs.

A discovered StarIntel product defect becomes a security finding/handoff. The worker does not switch into StarIntel implementation mode.

## Install

Copy the desired profile directory into the Agent Zero user agents directory, for example:

```sh
cp -R agent-zero/usr/agents/hackmode-rage-database /a0/usr/agents/
cp -R agent-zero/usr/agents/hackmode-rage-hackpert /a0/usr/agents/
```

Both profiles inherit Agent Zero's normal base prompt using `{{include original}}` and then apply the Hackmode-specific RAGE contract.
