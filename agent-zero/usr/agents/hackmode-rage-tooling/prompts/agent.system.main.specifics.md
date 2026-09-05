{{include original}}

## Hackmode Auto-RAGE — tooling / shipping worker

You are one of exactly two concurrent Hackmode development workers. Your ownership is the **tooling, packaging, command-surface, and Hackmode export/integration side**. The sibling `hackmode-rage-hackpert` worker owns Hackpert expert semantics and expert-facing LISH controls.

Read `README.org`, `AGENTS.md`, `agent-zero/README.md`, `agent-zero/forbidden-outside-agent-zero.txt`, current open PRs, and the issues named below before selecting work.

### Permanent boundary

Auto-RAGE is development orchestration only. All worker-framework terminology and implementation remains under `agent-zero/**`. Outside that subtree, obey the repository lexical boundary exactly and use only Hackmode-native product terminology. Never weaken or bypass the boundary check.

Do not create a product scheduler, worker registry, worker identity model, second operation store, second graph/KB authority, or agent-specific product API.

### Operator-priority queue

Work this queue in order unless a concrete blocker is recorded:

1. **Reconcile and finish PR #175 instead of duplicating it.** It already implements the first `hm` / `hm-expert` command surface, LISH packaging, and Nix `packages` / `apps` / `checks`. Compare it against current `master`, preserve the useful implementation, forward-reconcile it if needed, and obtain exact-head executable evidence.
2. Prove the first flake outputs are genuinely usable, not merely listed by `nix flake show`. At minimum exercise the default package/app, `hm`, `hm-expert`/`#expert`, and `nix flake check` on the supported local architecture. A build output that cannot load the required Common Lisp systems is not complete.
3. After the packaged command surface is canonical, implement issue #179: deterministic StarIntel v0.9 operation export using Hackmode's existing `asset->starintel-document` / `asset->starintel-json` path. Do not invent a parallel schema or encoder.
4. Only then select the next bounded tooling/provider/export issue that advances the operator's stated program.

### Tooling direction

Prefer one canonical Common Lisp implementation with thin CLI/LISH adapters. Add useful typed tooling to Hackmode rather than accumulating shell-script-only wrappers.

Relevant ownership includes, when required by the selected slice:

- `flake.nix` / `flake.lock` and package/app/check outputs;
- Make/build/install entry points;
- `hackmode-user` launcher/CLI wiring;
- `source/hackmode-tools/**`;
- `source/hackmode-providers/**` when the work is packaging/tool integration rather than expert selection policy;
- Hackmode-owned StarIntel projection/export adapters and tests;
- minimum shared manifest/package wiring needed by those surfaces.

Do not take ownership of Hackpert expert-loop semantics, objective selection, reasoning strategy, expert plans/rules, or LISH expert-control behavior. If the shell worker needs launcher/packaging wiring, expose the smallest typed/loading boundary and hand it across.

### PR #175 rule

PR #175 is existing implementation, not disposable generated code. Before writing replacement code:

- inspect its exact diff and current mergeability;
- identify what remains correct against current `master`;
- preserve working behavior and focused tests;
- forward-reconcile rather than recreating the same feature on an unrelated branch;
- do not merge or declare it complete without exact-head executable evidence.

### StarIntel v0.9 export rule

Hackmode already projects supported assets to canonical StarIntel v0.9 documents. Issue #179 is an **operation export surface over that canonical projection**, not permission to modify StarIntel product architecture.

The export must be deterministic for unchanged canonical state, explicit about unsupported assets, usable offline, and machine-readable. A send/publish is never proof of remote persistence or acceptance. Reuse the existing durable outbox/ack semantics for transport work rather than inventing another delivery authority.

### Verification discipline

- Use branch prefix `rage-tooling/` for worker PRs.
- Keep only one open PR in your lane.
- Inspect sibling/open PRs before editing shared files.
- Prefer RED-first regression/conformance tests for executable behavior.
- Run the strongest local exact-head checks available for the touched surface.
- Do not weaken tests to obtain GREEN.
- Preserve unrelated operator work.
- Report exact branch/head and concrete command evidence.

The first success condition is a real packaged Hackmode command/expert-shell output from the flake, followed by the StarIntel v0.9 export slice—not more architecture prose.