# Hackmode Auto-RAGE workers

Hackmode owns two active development workers. They are development orchestration only; Hackmode product/runtime code must continue to use Hackmode-native concepts and must not grow worker-framework abstractions.

The active profiles are:

- `hackmode-rage-tooling` — packaging, Nix/flake outputs, command/tool integration, LISH runtime packaging, and Hackmode-to-StarIntel v0.9 export surfaces.
- `hackmode-rage-hackpert` — Hackpert expert-engine behavior and first-class LISH expert/operator controls.

The two workers use separate branches/worktrees and must inspect current open Hackmode PRs before claiming a slice. They must not duplicate already-implemented work or edit each other's owned implementation area merely to unblock themselves.

## Current program

The immediate ordered queue is intentionally narrow:

1. `hackmode-rage-tooling` owns reconciliation and exact-head verification of PR #175 (`hm`, `hm-expert`, LISH packaging, and first flake `packages`/`apps`/`checks`). Do not rewrite that implementation from scratch when it can be reconciled.
2. `hackmode-rage-hackpert` owns issue #178: make `hm-expert` a real LISH control/inspection surface over the existing Hackpert typed APIs. Coordinate with #175 rather than duplicating its launcher/flake work.
3. After the packaged command surface is canonical, `hackmode-rage-tooling` owns issue #179: deterministic StarIntel v0.9 operation export using Hackmode's existing canonical projection path.

The workers may continue to the next unblocked bounded Hackmode issue only after these operator-priority slices are complete or concretely blocked.

## Product boundary

`AGENTS.md` and `forbidden-outside-agent-zero.txt` are authoritative. Development-worker terminology and implementation stay under `agent-zero/**`.

Outside this subtree, use only product concepts such as operations, assets, providers, expert runs, typed actions, evidence, graph/KB state, LISH commands, packages, applications, checks, and export interfaces. Never create product-runtime abstractions for worker identity, scheduling, lane ownership, task selection, authorization, coordination, or lifecycle.

StarIntel is an integration target, not a second Hackmode authority. Hackmode may project/export accepted Hackmode data through canonical StarIntel v0.9 interfaces, but these workers do not perform ordinary StarIntel product development.

## Install

Copy both profiles into the Agent Zero user-agent directory:

```sh
sh agent-zero/install.sh /a0/usr
```

The default target is `/a0/usr` when no argument is supplied.

## PR lanes

`pr-lanes.txt` defines one open PR lane per active worker. The repository serialization workflow consumes that file. Keep worker PRs focused and verify the exact head before reporting a slice complete.
