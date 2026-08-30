# Hackmode Auto-RAGE workers

The autonomous development-worker home is Hackmode, not StarIntel Auto-Research.

Two initial Agent Zero profiles intentionally have disjoint ownership:

- `hackmode-rage-database` — Hackmode database, execution graph, operational/long-term KB persistence, promotion/export plumbing, and persistence tests.
- `hackmode-rage-hackpert` — Hackpert expert engine, passive/active orchestration, Prolog rules/interfaces, plans/playbooks, provider-action integration, and LISH expert controls.

Use separate worktrees/branches and separate worker/run identities. A worker must inspect current open Hackmode PRs before claiming work. It must not edit the other worker's owned implementation area merely to unblock itself; define or request a typed boundary and hand the dependency across instead.

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
