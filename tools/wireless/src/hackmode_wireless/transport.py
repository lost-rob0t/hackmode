"""Schema boundary and publication transports for hackmode-wireless.

The StarIntel 0.10.1 release (being minted in the canonical schema repo)
introduces the ``wireless-network`` and ``wireless-station`` dtypes.  Until
that release is published, the ``starintel-doc`` package does not know these
dtypes, so this module:

* validates the StarIntel v0.9-line envelope against the bundled v0.9.0 base
  schema (dtype enum locally extended with the two wireless dtypes), and
* applies a supplemental local validator implementing the 0.10.1 wireless
  data contracts (required fields, enums, type checks,
  ``additionalProperties: false`` on ``data``).

Documents are published only through RabbitMQ (durable topic exchange
``documents``, routing key ``documents.ingest.<dtype>``, publisher confirms,
at-least-once with deterministic ids) or the offline JSONL sink.

Deterministic identity
----------------------

- ``wireless-network`` keyed on ``(bssid, ssid-normalized, source_network_id)``
- ``wireless-station`` keyed on ``(mac, source_device_id)``
- ``_id = starintel:<dtype>:<sha256-of-identity-key>`` where the identity key
  is the unit-separator join of the key parts.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import sys
import time
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Protocol

from jsonschema import Draft202012Validator, FormatChecker

LOGGER = logging.getLogger(__name__)

SCHEMA_VERSION = "0.9.0"
"""Immutable base/wire schema family; the wireless release is 0.10.1 (pending)."""

DOCUMENTS_EXCHANGE = "documents"
DEFAULT_RABBIT_URL = "amqp://guest:guest@127.0.0.1:5672/%2F"
BASE_SCHEMA_FILENAME = "starintel-doc-v0.9.0.base.schema.json"
MANIFEST_ROUTING_KEY = "documents.ingest.actor-manifest"

WIRELESS_NETWORK_DTYPE = "wireless-network"
WIRELESS_STATION_DTYPE = "wireless-station"
WIRELESS_DTYPES: tuple[str, ...] = (WIRELESS_NETWORK_DTYPE, WIRELESS_STATION_DTYPE)

JsonObject = dict[str, Any]
Document = dict[str, Any]

_ROUTING_KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")


class NetworkContractError(ValueError):
    """Permanent boundary error for an invalid StarIntel document."""


# --------------------------------------------------------------------------
# Wireless dtype contracts (StarIntel 0.10.1, supplemental until published)
# --------------------------------------------------------------------------

SECURITY_ENUM: tuple[str, ...] = (
    "open",
    "wep",
    "wpa-psk",
    "wpa2-psk",
    "wpa2-enterprise",
    "wpa3-psk",
    "wpa3-enterprise",
    "wpa2wpa3-psk",
    "unknown",
)
BAND_ENUM: tuple[str, ...] = ("2.4ghz", "5ghz", "6ghz", "unknown")
STATION_TYPE_ENUM: tuple[str, ...] = ("station", "ap", "bridge", "bridge-ap", "unknown")

# kind: "string" | "integer" | "number" | "datetime" | "string-array" | ("enum", values)
_FieldKind = str | tuple[str, tuple[str, ...]]

WIRELESS_NETWORK_SPEC: dict[str, tuple[_FieldKind, bool]] = {
    # (kind, required)
    "bssid": ("string", True),
    "ssid": ("string", False),
    "security": (("enum", SECURITY_ENUM), True),
    "cipher_suite": ("string", False),
    "auth_mode": ("string", False),
    "channel": ("integer", False),
    "frequency_mhz": ("integer", False),
    "band": (("enum", BAND_ENUM), False),
    "signal_dbm": ("integer", False),
    "latitude": ("number", False),
    "longitude": ("number", False),
    "location_accuracy_m": ("number", False),
    "observations": ("integer", False),
    "client_count": ("integer", False),
    "first_seen": ("datetime", False),
    "last_seen": ("datetime", False),
    "source_network_id": ("string", False),
    "vendor": ("string", False),
    "hosted_host_id": ("string", False),
    "qos": ("integer", False),
}

WIRELESS_STATION_SPEC: dict[str, tuple[_FieldKind, bool]] = {
    "mac": ("string", True),
    "station_type": (("enum", STATION_TYPE_ENUM), False),
    "vendor": ("string", False),
    "probe_ssids": ("string-array", False),
    "last_bssid": ("string", False),
    "signal_dbm": ("integer", False),
    "observations": ("integer", False),
    "first_seen": ("datetime", False),
    "last_seen": ("datetime", False),
    "source_device_id": ("string", False),
    "packets": ("integer", False),
    "data_bytes": ("integer", False),
}

_DATETIME_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:?\d{2})?$"
)


def _is_iso_datetime(value: object) -> bool:
    if not isinstance(value, str) or _DATETIME_RE.match(value) is None:
        return False
    normalized = value.replace(" ", "T", 1)
    if normalized.endswith(("Z", "z")):
        normalized = normalized[:-1] + "+00:00"
    try:
        datetime.fromisoformat(normalized)
    except ValueError:
        return False
    return True


def _check_field(
    dtype: str, data: Mapping[str, Any], name: str, spec: tuple[_FieldKind, bool]
) -> list[str]:
    kind, required = spec
    errors: list[str] = []
    if name not in data or data[name] is None:
        if required:
            errors.append(f"{dtype}.data.{name}: required field is missing")
        return errors
    value = data[name]
    if isinstance(kind, tuple):
        _, values = kind
        if value not in values:
            errors.append(f"{dtype}.data.{name}: {value!r} not in enum {list(values)}")
        return errors
    if kind == "string":
        if not isinstance(value, str):
            errors.append(f"{dtype}.data.{name}: expected string, got {type(value).__name__}")
        return errors
    if kind == "integer":
        # bool is an int subclass; reject it explicitly.
        if isinstance(value, bool) or not isinstance(value, int):
            errors.append(f"{dtype}.data.{name}: expected integer, got {type(value).__name__}")
        return errors
    if kind == "number":
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            errors.append(f"{dtype}.data.{name}: expected number, got {type(value).__name__}")
        return errors
    if kind == "datetime":
        if not _is_iso_datetime(value):
            errors.append(f"{dtype}.data.{name}: {value!r} is not an ISO-8601 datetime")
        return errors
    if kind == "string-array":
        valid = isinstance(value, list) and all(isinstance(item, str) for item in value)
        if not valid:
            errors.append(f"{dtype}.data.{name}: expected array of strings")
        return errors
    return errors


def validate_wireless_data(dtype: str, data: object) -> None:
    """Validate the ``data`` object of a wireless dtype against 0.10.1 contracts."""
    spec = WIRELESS_NETWORK_SPEC if dtype == WIRELESS_NETWORK_DTYPE else WIRELESS_STATION_SPEC
    if not isinstance(data, dict):
        raise NetworkContractError(f"{dtype}.data: expected object, got {type(data).__name__}")
    errors: list[str] = []
    unknown = sorted(set(data) - set(spec))
    for name in unknown:
        errors.append(f"{dtype}.data.{name}: additional property not allowed")
    for name in sorted(spec):
        errors.extend(_check_field(dtype, data, name, spec[name]))
    if errors:
        raise NetworkContractError("; ".join(errors))


# --------------------------------------------------------------------------
# Deterministic identity
# --------------------------------------------------------------------------


def identity_digest(parts: Sequence[str]) -> str:
    """SHA-256 over the unit-separator join of the identity key parts."""
    return hashlib.sha256("\x1f".join(parts).encode("utf-8")).hexdigest()


def deterministic_id(dtype: str, parts: Sequence[str]) -> str:
    """Stable document id: ``starintel:<dtype>:<sha256-of-identity-key>``."""
    return f"starintel:{dtype}:{identity_digest(parts)}"


def normalize_ssid(ssid: object) -> str:
    """SSID normalization used for identity: trim, casefold, squeeze spaces."""
    if not isinstance(ssid, str):
        return ""
    return re.sub(r"\s+", " ", ssid.strip()).casefold()


def normalize_mac(mac: object) -> str:
    """Normalize a MAC/BSSID to lowercase, colon-separated octets."""
    if not isinstance(mac, str):
        return ""
    hexdigits = re.sub(r"[^0-9a-fA-F]", "", mac)
    if len(hexdigits) != 12:
        return mac.strip().lower()
    return ":".join(hexdigits[i : i + 2] for i in range(0, 12, 2)).lower()


def wireless_network_id(bssid: str, ssid: object, source_network_id: object) -> str:
    """Deterministic wireless-network id over (bssid, ssid-normalized, source_network_id)."""
    return deterministic_id(
        WIRELESS_NETWORK_DTYPE,
        (normalize_mac(bssid), normalize_ssid(ssid), str(source_network_id or "")),
    )


def wireless_station_id(mac: str, source_device_id: object) -> str:
    """Deterministic wireless-station id over (mac, source_device_id)."""
    return deterministic_id(
        WIRELESS_STATION_DTYPE,
        (normalize_mac(mac), str(source_device_id or "")),
    )


# --------------------------------------------------------------------------
# Envelope construction
# --------------------------------------------------------------------------


def now_iso() -> str:
    return datetime.now(UTC).isoformat()


def build_envelope(
    *,
    _id: str,
    dtype: str,
    dataset: str,
    data: JsonObject,
    sources: Sequence[JsonObject],
    evidence: Sequence[JsonObject] | None = None,
    now: str | None = None,
) -> Document:
    """Build a StarIntel v0.9-line envelope around one dtype payload."""
    timestamp = now or now_iso()
    return {
        "_id": _id,
        "dataset": dataset,
        "dtype": dtype,
        "schema_version": SCHEMA_VERSION,
        "version": 1,
        "date_added": timestamp,
        "date_updated": timestamp,
        "sources": [dict(source) for source in sources],
        "evidence": [dict(item) for item in (evidence or [])],
        "data": data,
    }


def relation_document(
    *,
    subject: str,
    predicate: str,
    obj: str,
    dataset: str,
    now: str,
    sources: Sequence[JsonObject],
    note: str = "",
) -> Document:
    """Deterministic relation document (base v0.9 ``relation`` dtype)."""
    document = build_envelope(
        _id=deterministic_id("relation", (subject, predicate, obj)),
        dtype="relation",
        dataset=dataset,
        data={
            "subject": subject,
            "predicate": predicate,
            "object": obj,
            "directed": True,
            "confidence": 1.0,
            "source": subject,
            "target": obj,
            "qualifiers": {},
            "note": note,
        },
        sources=sources,
        now=now,
    )
    document["related_ids"] = [subject, obj]
    document["title"] = f"{subject} {predicate} {obj}"
    return document


# --------------------------------------------------------------------------
# Schema boundary
# --------------------------------------------------------------------------


class SchemaBoundary:
    """Envelope validation against the base v0.9.0 schema plus 0.10.1 contracts.

    The bundled base schema's ``dtype`` enum is extended with the wireless
    dtypes; their ``data`` payloads are validated by
    :func:`validate_wireless_data` instead of the (not yet published)
    starintel-doc implementation.
    """

    def __init__(self, schema: JsonObject, source: str, extra_dtypes: Sequence[str] = ()) -> None:
        self.schema = schema
        self.source = source
        dtype = schema.get("properties", {}).get("dtype", {})
        enum = dtype.get("enum")
        if not isinstance(enum, list):
            raise NetworkContractError("base schema dtype enum is missing")
        extended = list(enum)
        for value in extra_dtypes:
            if value not in extended:
                extended.append(value)
        self.schema["properties"]["dtype"]["enum"] = extended
        self._validator = Draft202012Validator(self.schema, format_checker=FormatChecker())

    @classmethod
    def from_path(cls, path: str | Path, extra_dtypes: Sequence[str] = ()) -> SchemaBoundary:
        source = Path(path)
        try:
            value = json.loads(source.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise NetworkContractError(f"cannot load StarIntel schema {source}: {exc}") from exc
        if not isinstance(value, dict):
            raise NetworkContractError("StarIntel schema must be a JSON object")
        return cls(value, str(source), extra_dtypes)

    @classmethod
    def default(cls) -> SchemaBoundary:
        bundled = Path(__file__).parent / "schemas" / BASE_SCHEMA_FILENAME
        return cls.from_path(bundled, WIRELESS_DTYPES)

    def validate(self, document: Mapping[str, Any]) -> JsonObject:
        candidate = dict(document)
        errors = sorted(
            self._validator.iter_errors(candidate), key=lambda error: list(error.absolute_path)
        )
        if errors:
            detail = "; ".join(
                f"{'/'.join(str(part) for part in error.absolute_path) or '<root>'}: {error.message}"
                for error in errors
            )
            raise NetworkContractError(f"envelope validation failed: {detail}")
        # jsonschema format checking is advisory without rfc3339-validator;
        # enforce envelope datetimes explicitly.
        for field in ("date_added", "date_updated"):
            if not _is_iso_datetime(candidate.get(field)):
                raise NetworkContractError(f"envelope.{field}: not an ISO-8601 datetime")
        dtype = candidate.get("dtype")
        if dtype in WIRELESS_DTYPES:
            validate_wireless_data(dtype, candidate.get("data"))
        return candidate


# --------------------------------------------------------------------------
# RabbitMQ / JSONL transports
# --------------------------------------------------------------------------


def document_ingest_routing_key(dtype: str) -> str:
    value = dtype.strip().lower()
    if not value or _ROUTING_KEY_RE.fullmatch(value) is None:
        raise NetworkContractError(f"invalid document dtype: {dtype!r}")
    return f"documents.ingest.{value}"


def rabbit_url_from_env() -> str | None:
    """Resolve the broker URL from STARINTEL_RABBITMQ_URL (alias STARINTEL_RABBIT_URL)."""
    return os.environ.get("STARINTEL_RABBITMQ_URL") or os.environ.get("STARINTEL_RABBIT_URL") or None


@dataclass(frozen=True, slots=True)
class RabbitConfig:
    """Connection and publication policy for the StarIntel documents exchange."""

    url: str = DEFAULT_RABBIT_URL
    exchange: str = DOCUMENTS_EXCHANGE
    publish_retries: int = 3
    publish_retry_delay: float = 0.5

    @classmethod
    def from_env(cls) -> RabbitConfig:
        url = rabbit_url_from_env() or DEFAULT_RABBIT_URL
        exchange = os.environ.get("STARINTEL_RABBITMQ_EXCHANGE") or os.environ.get(
            "STARINTEL_RABBIT_EXCHANGE", DOCUMENTS_EXCHANGE
        )
        return cls(url=url, exchange=exchange)


class PublishTransport(Protocol):
    """Sink for schema-validated canonical documents."""

    def publish(self, document: Document) -> str:
        """Publish one document; returns the ingest routing key."""

    def close(self) -> None: ...


class ValidatingPublisher:
    """Validate through the boundary, then hand to the transport sink.

    Every emission path (actors, CLI, manifests) goes through this class so
    an invalid document can never reach the broker or the JSONL sink.
    """

    def __init__(self, boundary: SchemaBoundary, sink: PublishTransport) -> None:
        self.boundary = boundary
        self.sink = sink

    def publish(self, document: Document) -> str:
        validated = self.boundary.validate(document)
        return self.sink.publish(validated)

    def publish_all(self, documents: Iterable[Document]) -> int:
        published = 0
        for document in documents:
            self.publish(document)
            published += 1
        return published

    def close(self) -> None:
        self.sink.close()


class RabbitPublisher:
    """Pika publisher: durable topic exchange, confirms, at-least-once.

    A ``connection_factory`` can be injected for hermetic tests; production
    builds a :class:`pika.BlockingConnection` from ``config.url``.
    """

    def __init__(
        self,
        config: RabbitConfig,
        boundary: SchemaBoundary,
        *,
        connection_factory: Any | None = None,
    ) -> None:
        self.config = config
        self.boundary = boundary
        self._connection_factory = connection_factory
        self._connection: Any | None = None
        self._channel: Any | None = None

    def _connect(self) -> Any:
        if self._connection is None or not self._connection.is_open:
            if self._connection_factory is not None:
                self._connection = self._connection_factory()
            else:
                import pika

                self._connection = pika.BlockingConnection(pika.URLParameters(self.config.url))
            self._channel = None
        if self._channel is None or not self._channel.is_open:
            self._channel = self._connection.channel()
            self._channel.exchange_declare(
                exchange=self.config.exchange,
                exchange_type="topic",
                durable=True,
            )
            self._channel.confirm_delivery()
        return self._channel

    def _reset(self) -> None:
        channel, connection = self._channel, self._connection
        self._channel, self._connection = None, None
        for closable in (channel, connection):
            if closable is not None and getattr(closable, "is_open", False):
                try:
                    closable.close()
                except Exception:  # pragma: no cover - best-effort cleanup
                    LOGGER.debug("closing stale AMQP handle failed", exc_info=True)

    def publish(self, document: Document) -> str:
        validated = self.boundary.validate(document)
        dtype = validated["dtype"]
        routing_key = document_ingest_routing_key(dtype)
        body = json.dumps(validated, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        last_error: Exception | None = None
        for attempt in range(1, self.config.publish_retries + 1):
            try:
                self._connect().basic_publish(
                    exchange=self.config.exchange,
                    routing_key=routing_key,
                    body=body,
                    mandatory=True,
                    properties=_basic_properties(dtype),
                )
                return routing_key
            except Exception as exc:  # NackError/UnroutableError/AMQPError/OSError
                last_error = exc
                if type(exc).__name__ == "UnroutableError":
                    raise NetworkContractError(f"unroutable publication: {exc}") from exc
                self._reset()
                if attempt < self.config.publish_retries:
                    time.sleep(self.config.publish_retry_delay)
        raise NetworkContractError(
            f"publish failed after {self.config.publish_retries} attempts: {last_error}"
        )

    def close(self) -> None:
        self._reset()


def _basic_properties(dtype: str) -> Any:
    import pika

    return pika.BasicProperties(
        content_type="application/json",
        content_encoding="utf-8",
        delivery_mode=2,
        type=dtype,
    )


class JsonlPublisher:
    """Offline sink: one canonical JSON document per line (sorted keys)."""

    def __init__(self, path: str | Path | None = None) -> None:
        self.path = Path(path) if path is not None else None
        self._handle: Any = None
        if self.path is not None:
            self._handle = self.path.open("a", encoding="utf-8")

    def publish(self, document: Document) -> str:
        line = json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        if self._handle is not None:
            self._handle.write(line + "\n")
        else:
            sys.stdout.write(line + "\n")
        return document_ingest_routing_key(str(document["dtype"]))

    def close(self) -> None:
        if self._handle is not None:
            self._handle.close()
            self._handle = None


def transport_from_env(
    boundary: SchemaBoundary,
    *,
    jsonl_path: str | Path | None = None,
    rabbit_url: str | None = None,
) -> ValidatingPublisher:
    """Resolve the publication transport: ``--jsonl`` offline, else RabbitMQ."""
    if jsonl_path is not None:
        return ValidatingPublisher(boundary, JsonlPublisher(jsonl_path))
    base = RabbitConfig.from_env()
    config = RabbitConfig(
        url=rabbit_url or base.url,
        exchange=base.exchange,
        publish_retries=base.publish_retries,
        publish_retry_delay=base.publish_retry_delay,
    )
    return ValidatingPublisher(boundary, RabbitPublisher(config, boundary))


__all__ = [
    "BAND_ENUM",
    "DOCUMENTS_EXCHANGE",
    "JsonlPublisher",
    "MANIFEST_ROUTING_KEY",
    "NetworkContractError",
    "PublishTransport",
    "RabbitConfig",
    "RabbitPublisher",
    "SCHEMA_VERSION",
    "SECURITY_ENUM",
    "STATION_TYPE_ENUM",
    "SchemaBoundary",
    "ValidatingPublisher",
    "build_envelope",
    "deterministic_id",
    "document_ingest_routing_key",
    "identity_digest",
    "normalize_mac",
    "normalize_ssid",
    "now_iso",
    "rabbit_url_from_env",
    "relation_document",
    "transport_from_env",
    "validate_wireless_data",
    "wireless_network_id",
    "wireless_station_id",
]
