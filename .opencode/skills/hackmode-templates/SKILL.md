---
name: hackmode-templates
description: Create Hackmode operation workspaces from the template set (bbp program, generic op, htb machine); run this skill when scaffolding a new operation or editing anything under hackmode templates/
---

# hackmode-templates — scaffolding operation workspaces

A template is a *directory* that clients copy when creating an operation
workspace. Templates are static content (Org files + seed files): they
declare the starting shape of an operation and never own state.

| template      | purpose                                    |
|---------------+--------------------------------------------|
| `templates/bbp/` | bug-bounty program operation (scope table + methodology checklists) |
| `templates/op/`  | generic operation (About/Goals/Phases, assets, targets, tasks) |
| `templates/htb/` | single-machine / CTF operation (flags table, foothold→privesc phases) |

`templates/bounty/` is not part of the set; do not copy or extend it.

## Creating an operation from a template (current contract)

`op_create` persists the registry record and creates the workspace
directory. Seeding is a client step — copy a template in:

```
op_create { "name": "acme-bounty" }
cp -r ~/starintel/hackmode/templates/bbp/* ~/hackmode/acme-bounty/
```

The Emacs client (`hackmode-create-operation`) does the copy for you when
you create operations there. The Common Lisp runtime reads no template
file — it only owns `<workspace>/.hackmode/` (Tek9).

## Client-managed territory (never template-owned)

`.config/`, `findings/`, `checklists/`, `scans/`, and `.envrc` belong to
the clients at runtime. Templates may seed `.config/` *files* only
(`targets.txt`, `blacklist.txt`); clients create and overwrite
idempotently. Never move operation state into a template or vice versa.

## Rules for new templates

1. Content is data — no code the runtime must understand.
2. No machine-specific endpoints or credentials, ever.
3. Tool-coverage notes name Hackmode capabilities (`:subdomain-enumerate`,
   `:dns-resolve`, `:vuln-scan`, `:http-probe`) and spell out backend
   status ("backend pending") rather than implying coverage.
4. Evidence references, not evidence copies: reports link asset ids from
   the operation store.
5. Templates are consumed by directory copy — extra files are harmless,
   but anything a client must enforce belongs to the client, not here.

## Install gap

Clients read templates from `~/.config/hackmode/templates`:

```
mkdir -p ~/.config/hackmode/templates
cp -r ~/starintel/hackmode/templates/* ~/.config/hackmode/templates/
```
