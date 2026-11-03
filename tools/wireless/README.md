# hackmode wireless recon tools

WiGLE + Kismet wireless recon collectors that emit StarIntel documents
(`wireless-network`, `wireless-station`, plus `relation`/`host` follow-ups).
First-party fold of the former standalone repository, which is now
superseded by hackmode.

Invariant: every capability ships in dual form — a Pykka actor system and a
one-shot `hm-wireless` subcommand — both building identical documents
through the same validating publisher.

Publishing contract: RabbitMQ only (durable topic exchange `documents`,
routing key `documents.ingest.<dtype>`, publisher confirms, deterministic
ids for at-least-once replay), or the offline JSONL sink via `--jsonl`.

Commands (from `tools/wireless`, after `python3 -m venv .venv` and
`.venv/bin/pip install -e '.[dev]'`):

    .venv/bin/hm-wireless wigle search --bbox "1.0,2.0,3.0,4.0" --jsonl out.jsonl
    .venv/bin/hm-wireless kismet poll --url http://kismet:2501 --once --jsonl out.jsonl
    .venv/bin/hm-wireless manifests --jsonl out.jsonl

Tests and gates: `.venv/bin/pytest -q`, `.venv/bin/ruff check .`,
`.venv/bin/mypy` — all hermetic (no live network or broker).

Schema lock: pinned by the repository-level lock at
`../../schema/starintel-schema.lock.json` (relative to this directory);
envelope validation uses the bundled v0.9.0 base schema until the canonical
0.10.1 release lands. See `tests/test_schema_lock.py`.
