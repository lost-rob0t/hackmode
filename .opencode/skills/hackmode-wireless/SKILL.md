---
name: hackmode-wireless
description: Operate Hackmode wireless recon (WiGLE + Kismet collectors emitting StarIntel documents via hm-wireless); run this skill for any wireless engagement, collector deployment, or wireless document publishing
---

# hackmode-wireless — wireless recon collectors

`tools/wireless/` in the Hackmode checkout is the first-party wireless
recon tooling: WiGLE and Kismet collectors that emit StarIntel documents
(`wireless-network`, `wireless-station`, plus `relation`/`host`
follow-ups) into the standard document pipeline.

## Dual form — actors and one-shot CLI

Every capability ships in two forms that build identical documents
through the same validating publisher:

- a Pykka actor system for long-running collection
- the one-shot `hm-wireless` CLI for interactive and scripted use

Prefer the actor form for daemon-style collection and the CLI for one
off pulls; never fork a third path around the publisher.

## Setup and commands

```
cd ~/starintel/hackmode/tools/wireless
python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'
.venv/bin/hm-wireless --help          # discover subcommands first
.venv/bin/hm-wireless wigle search --bbox "1.0,2.0,3.0,4.0" --jsonl out.jsonl
.venv/bin/hm-wireless kismet poll --url http://kismet:2501 --once --jsonl out.jsonl
.venv/bin/hm-wireless manifests --jsonl out.jsonl
```

Discover available subcommands and flags with `--help` at runtime; the
help output is the authority for the installed version.

## Publishing contract

- Brokered: RabbitMQ only — durable topic exchange `documents`, routing
  key `documents.ingest.<dtype>`, publisher confirms, deterministic ids
  for at-least-once replay.
- Offline: `--jsonl` writes documents to a local sink without a broker.
- A broker send is not proof of persistence — publisher confirms are the
  acknowledgment; verify delivery before claiming ingestion.

## Verification gates

```
.venv/bin/pytest -q        # hermetic: no live network or broker
.venv/bin/ruff check .
.venv/bin/mypy
```

Envelope validation uses the schema pinned by the repository-level lock
(`schema/starintel-schema.lock.json`). Never hand-edit schema version
values; the lock is resolved with the canonical schema repository's
release tooling, not from filenames or memory.

## Rules that do not bend

- Documents flow through the validating publisher; raw provider payloads
  never bypass it.
- Evidence stays lossless: collectors emit what was observed, no
  redaction or omission of observed fields.
- Keep collection operation-scoped: run wireless work under an operation
  like any other recon capability.
