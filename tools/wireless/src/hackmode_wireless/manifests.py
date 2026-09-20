"""Actor-manifest registry for hackmode-wireless (mirrors pro-actors manifests).

Emits ``actor-manifest`` documents on the StarIntel v0.9-line envelope with
the ``starintel.actor_manifest.v1`` extension contract, published to
``documents.ingest.actor-manifest`` over the same RabbitMQ transport.
"""

from __future__ import annotations

import argparse
import json
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import UTC, datetime

from hackmode_wireless.transport import (
    MANIFEST_ROUTING_KEY,
    SCHEMA_VERSION,
    Document,
    JsonObject,
    ValidatingPublisher,
)

MANIFEST_PROTOCOL_VERSION = "1.1.0"
IMPLEMENTATION_REPOSITORY = "lost-rob0t/hackmode"
IMPLEMENTATION_VERSION = "0.1.0"
DEFAULT_EXCHANGE = "documents"


@dataclass(frozen=True, slots=True)
class ActorManifestSpec:
    actor_id: str
    actor_type: str
    entrypoint: str
    runtime: str
    operations: tuple[str, ...] = ()
    input_dtypes: tuple[str, ...] = ()
    output_dtypes: tuple[str, ...] = ()
    dependencies: tuple[str, ...] = ()
    routing_keys: tuple[str, ...] = ()
    target_options: tuple[JsonObject, ...] = ()
    configuration_schema: JsonObject = field(default_factory=dict)
    capabilities: tuple[str, ...] = ()
    lifecycle: JsonObject = field(default_factory=dict)
    authorization: JsonObject = field(default_factory=dict)
    consumer_path: str | None = None


def _config(**properties: JsonObject) -> JsonObject:
    return {
        "type": "object",
        "additionalProperties": False,
        "properties": properties,
    }


ACTOR_MANIFESTS: dict[str, ActorManifestSpec] = {
    "wigle": ActorManifestSpec(
        actor_id="wigle",
        actor_type="collector",
        entrypoint="hackmode_wireless.wigle.actors:WigleActorSystem",
        runtime="python-asyncio-actor-system",
        operations=("search", "network-detail", "bluetooth-search"),
        input_dtypes=("target",),
        output_dtypes=("wireless-network", "host"),
        dependencies=("httpx",),
        routing_keys=("documents.ingest.<dtype>",),
        target_options=(
            {"key": "bbox", "type": "string", "description": "lat1,lon1,lat2,lon2 bounding box"},
            {"key": "ssid", "type": "string"},
            {"key": "netid", "type": "string"},
            {"key": "onlymine", "type": "boolean", "default": False},
            {"key": "max_pages", "type": "integer", "minimum": 1, "default": 10},
            {"key": "emit_hosts", "type": "boolean", "default": False},
        ),
        configuration_schema=_config(
            STARINTEL_WIGLE_API_NAME={"type": "string", "writeOnly": True},
            STARINTEL_WIGLE_API_TOKEN={"type": "string", "writeOnly": True},
            STARINTEL_WIGLE_BASE_URL={"type": "string", "format": "uri"},
            dataset={"type": "string", "default": "wigle"},
        ),
        capabilities=(
            "wigle-network-search",
            "bbox-and-ssid-targets",
            "searchafter-pagination",
            "bluetooth-search",
            "deterministic-identity",
            "rate-limited-politeness",
        ),
        lifecycle={"startup": "local", "shutdown": "drain actor mailboxes"},
        authorization={
            "credentials": "operator-supplied WiGLE API name/token (Basic auth)",
            "dataset_restrictions": [],
        },
    ),
    "kismet": ActorManifestSpec(
        actor_id="kismet",
        actor_type="continuous-collector",
        entrypoint="hackmode_wireless.kismet.actors:KismetActorSystem",
        runtime="python-asyncio-actor-system",
        operations=("poll", "poll-once", "status"),
        input_dtypes=("target",),
        output_dtypes=("wireless-network", "wireless-station", "relation"),
        dependencies=("httpx",),
        routing_keys=("documents.ingest.<dtype>",),
        target_options=(
            {"key": "url", "type": "string", "format": "uri", "required": True},
            {"key": "poll_interval", "type": "number", "exclusiveMinimum": 0, "default": 30.0},
            {"key": "once", "type": "boolean", "default": False},
        ),
        configuration_schema=_config(
            KISMET_TOKEN={"type": "string", "writeOnly": True},
            KISMET_USER={"type": "string", "writeOnly": True},
            KISMET_PASSWORD={"type": "string", "writeOnly": True},
            STARINTEL_KISMET_URL={"type": "string", "format": "uri"},
            dataset={"type": "string", "default": "kismet"},
            poll_interval={"type": "number", "exclusiveMinimum": 0, "default": 30.0},
        ),
        capabilities=(
            "kismet-rest-polling",
            "timestamp-delta-paging",
            "ap-and-client-mapping",
            "probe-ssid-capture",
            "observed-at-station-relations",
            "deterministic-identity",
        ),
        lifecycle={
            "startup": "local",
            "readiness": "first successful device poll",
            "shutdown": "cancel poll timer and drain actor mailboxes",
        },
        authorization={
            "credentials": "Kismet API token (KISMET cookie) or admin user/password",
            "dataset_restrictions": [],
        },
    ),
}


def manifest_ids_for_actor_names(actor_names: Iterable[str]) -> tuple[str, ...]:
    actor_ids = {
        actor_id
        for name in actor_names
        if (actor_id := name) in ACTOR_MANIFESTS
    }
    return tuple(sorted(actor_ids))


def actor_manifest_document(actor_id: str, *, now: str | None = None) -> Document:
    try:
        spec = ACTOR_MANIFESTS[actor_id]
    except KeyError as exc:
        raise KeyError(f"unknown actor manifest: {actor_id}") from exc

    timestamp = now or datetime.now(UTC).isoformat()
    data: JsonObject = {
        "actor": spec.actor_id,
        "manifest_type": "actor-runtime",
        "name": spec.actor_id,
        "target_options": [dict(option) for option in spec.target_options],
        "generated_at": timestamp,
        "schema_versions": [SCHEMA_VERSION],
    }
    if spec.consumer_path is not None:
        data["consumer_path"] = spec.consumer_path

    contract: JsonObject = {
        "protocol_version": MANIFEST_PROTOCOL_VERSION,
        "actor_id": spec.actor_id,
        "actor_type": spec.actor_type,
        "implementation": {
            "repository": IMPLEMENTATION_REPOSITORY,
            "version": IMPLEMENTATION_VERSION,
        },
        "entrypoint": spec.entrypoint,
        "runtime": spec.runtime,
        "operations": list(spec.operations),
        "input_dtypes": list(spec.input_dtypes),
        "output_dtypes": list(spec.output_dtypes),
        "dependencies": list(spec.dependencies),
        "routing_keys": list(spec.routing_keys),
        "configuration_schema": spec.configuration_schema,
        "capabilities": list(spec.capabilities),
        "lifecycle": spec.lifecycle,
        "authorization": spec.authorization,
        "schema_revision": SCHEMA_VERSION,
    }
    return {
        "_id": f"starintel:actor-manifest:{spec.actor_id}",
        "dataset": "starintel-system",
        "dtype": "actor-manifest",
        "schema_version": SCHEMA_VERSION,
        "version": 1,
        "date_added": timestamp,
        "date_updated": timestamp,
        "sources": [],
        "evidence": [],
        "data": data,
        "extensions": {"starintel.actor_manifest.v1": contract},
    }


def all_actor_manifest_documents(*, now: str | None = None) -> tuple[Document, ...]:
    timestamp = now or datetime.now(UTC).isoformat()
    return tuple(
        actor_manifest_document(actor_id, now=timestamp)
        for actor_id in sorted(ACTOR_MANIFESTS)
    )


def publish_actor_manifests(
    documents: Iterable[Document],
    rabbit_url: str,
    *,
    exchange: str = DEFAULT_EXCHANGE,
) -> int:
    """Publish manifests to the durable documents exchange with confirms."""
    import pika

    connection = pika.BlockingConnection(pika.URLParameters(rabbit_url))
    try:
        channel = connection.channel()
        channel.exchange_declare(exchange=exchange, exchange_type="topic", durable=True)
        channel.confirm_delivery()
        published = 0
        for document in documents:
            confirmed = channel.basic_publish(
                exchange=exchange,
                routing_key=MANIFEST_ROUTING_KEY,
                body=json.dumps(document, separators=(",", ":"), sort_keys=True).encode("utf-8"),
                mandatory=True,
                properties=pika.BasicProperties(
                    content_type="application/json",
                    content_encoding="utf-8",
                    delivery_mode=2,
                    type="actor-manifest",
                ),
            )
            if confirmed is False:
                raise RuntimeError(f"RabbitMQ NACK while publishing {document['_id']}")
            published += 1
        return published
    finally:
        if connection.is_open:
            connection.close()


def _selected_documents(actor_ids: list[str], now: str | None) -> tuple[Document, ...]:
    if not actor_ids:
        return all_actor_manifest_documents(now=now)
    unknown = sorted(set(actor_ids).difference(ACTOR_MANIFESTS))
    if unknown:
        raise ValueError(f"unknown actor manifest(s): {', '.join(unknown)}")
    return tuple(actor_manifest_document(actor_id, now=now) for actor_id in actor_ids)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="hm-wireless-manifests",
        description="Emit StarIntel actor manifests for hackmode-wireless.",
    )
    parser.add_argument(
        "--actor",
        action="append",
        default=[],
        help="emit only this actor id; repeat for multiple actors",
    )
    parser.add_argument(
        "--jsonl",
        help="append documents as JSONL to this path instead of stdout",
    )
    args = parser.parse_args(argv)

    try:
        documents = _selected_documents(args.actor, None)
    except ValueError as exc:
        parser.error(str(exc))

    if args.jsonl:
        from hackmode_wireless.transport import JsonlPublisher, SchemaBoundary

        publisher = ValidatingPublisher(SchemaBoundary.default(), JsonlPublisher(args.jsonl))
        publisher.publish_all(documents)
        publisher.close()
        return 0
    for document in documents:
        print(json.dumps(document, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
