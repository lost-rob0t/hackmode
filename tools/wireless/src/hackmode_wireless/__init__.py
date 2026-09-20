"""Hackmode wireless recon: WiGLE + Kismet collectors -> StarIntel documents.

Mirrors the starintel-pro-actors anatomy: an asyncio actor system
(:mod:`hackmode_wireless.actor`), a schema boundary with RabbitMQ/JSONL
transports (:mod:`hackmode_wireless.transport`), one actor package per
upstream source, and an ``hm-wireless`` CLI exposing every actor capability
as a one-shot tool.  The superseded starintel-network standalone repo is
folded into hackmode as this first-party tree.
"""

from hackmode_wireless.transport import (
    SCHEMA_VERSION,
    SchemaBoundary,
    build_envelope,
    deterministic_id,
)

__version__ = "0.1.0"

__all__ = [
    "SCHEMA_VERSION",
    "SchemaBoundary",
    "__version__",
    "build_envelope",
    "deterministic_id",
]
