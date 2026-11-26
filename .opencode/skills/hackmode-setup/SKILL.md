---
name: hackmode-setup
description: Build, install, and wire Hackmode (hm Lisp image, hm-mcp stdio MCP server, operation templates) for a checkout or AI client; run this skill when Hackmode is missing from PATH, the MCP server is unregistered, or templates are not installed
---

# hackmode-setup — build, install, and register Hackmode

Canonical checkout: `~/starintel/hackmode`. Hackmode is local-first: the
Common Lisp runtime owns operation and typed asset state; Emacs, shell,
and MCP clients call that boundary and keep no parallel authority.

## Build (NixOS: always inside the devshell)

```
cd ~/starintel/hackmode
nix develop -c make build      # hm    — LISH image (Common Lisp shell)
nix develop -c make build-mcp  # hm-mcp — MCP stdio server over canonical APIs
sudo make install              # copies hm to /usr/local/bin
make test                      # asdf test systems; MCP suite re-establishes
                               # provider registrations itself
```

User extension file: `~/.config/hackmode/init.lisp` (loaded by `hm`, NOT by
`hm-mcp` — a headless server image must not depend on LISH-oriented init).

## Register hm-mcp with an AI client

`hm-mcp` speaks newline-delimited JSON-RPC 2.0 over stdio, logs to stderr
only, exits 0 on EOF, and runs tools sequentially (one call at a time —
tool execution is synchronous). Register per project, same shape as the
lab's zap server in `opencode.json`:

```json
{
  "mcp": {
    "servers": {
      "hackmode": {
        "type": "local",
        "command": ["/home/unseen/starintel/hackmode/hm-mcp"]
      }
    }
  }
}
```

Server defaults: operations root `~/hackmode/` (override with
`HACKMODE_OPERATIONS_DIR`), protocol version negotiation
2024-11-05 / 2025-06-18, unknown tool = -32602, Lisp condition inside a
handler = `isError` result with the complete text. Never parse stdout of
the server as logs.

## Install operation templates

Clients read templates from `~/.config/hackmode/templates`:

```
mkdir -p ~/.config/hackmode/templates
cp -r ~/starintel/hackmode/templates/* ~/.config/hackmode/templates/
```

## Rules that do not bend

- Point clients at the canonical runtime (hm-mcp / LISH / Emacs package);
  never stand up a second operation DB, graph store, or registry.
- Build inside `nix develop -c` on NixOS; the devshell supplies sbcl, the
  Lisp library load path, and the security tooling backends.
- Generated binaries and FASLs are never committed.
- Execute external security tooling against authorized targets only.
