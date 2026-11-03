"""RabbitMQ publish path with a fake pika channel/connection."""

from __future__ import annotations

import json
from typing import Any

import pytest

from hackmode_wireless.transport import (
    NetworkContractError,
    RabbitConfig,
    RabbitPublisher,
    SchemaBoundary,
    wireless_network_id,
)


def network_document() -> dict[str, Any]:
    return {
        "_id": wireless_network_id("00:11:22:33:44:55", "net", "wigle:x"),
        "dataset": "test",
        "dtype": "wireless-network",
        "schema_version": "0.9.0",
        "version": 1,
        "date_added": "2026-09-19T00:00:00+00:00",
        "date_updated": "2026-09-19T00:00:00+00:00",
        "sources": [],
        "evidence": [],
        "data": {"bssid": "00:11:22:33:44:55", "security": "wpa2-psk", "ssid": "net"},
    }


class FakeChannel:
    is_open = True

    def __init__(self, failures: int = 0) -> None:
        self.failures = failures
        self.published: list[dict[str, Any]] = []
        self.exchange: dict[str, Any] | None = None
        self.confirmed = False

    def exchange_declare(self, **kwargs: Any) -> None:
        self.exchange = kwargs

    def confirm_delivery(self) -> None:
        self.confirmed = True

    def basic_publish(self, **kwargs: Any) -> bool:
        if self.failures > 0:
            self.failures -= 1
            raise RuntimeError("transient broker failure")
        self.published.append(kwargs)
        return True


class FakeConnection:
    def __init__(self, channel: FakeChannel) -> None:
        self._channel = channel
        self.is_open = True

    def channel(self) -> FakeChannel:
        return self._channel

    def close(self) -> None:
        self.is_open = False


def _publisher(channel: FakeChannel) -> RabbitPublisher:
    config = RabbitConfig(url="amqp://test", publish_retry_delay=0.0)
    return RabbitPublisher(
        config,
        SchemaBoundary.default(),
        connection_factory=lambda: FakeConnection(channel),
    )


def test_publish_declares_durable_topic_exchange_and_confirms() -> None:
    channel = FakeChannel()
    publisher = _publisher(channel)
    routing_key = publisher.publish(network_document())
    publisher.close()

    assert channel.exchange == {"exchange": "documents", "exchange_type": "topic", "durable": True}
    assert channel.confirmed
    assert routing_key == "documents.ingest.wireless-network"
    message = channel.published[0]
    assert message["exchange"] == "documents"
    assert message["routing_key"] == "documents.ingest.wireless-network"
    assert message["mandatory"] is True
    assert message["properties"].delivery_mode == 2
    assert message["properties"].content_type == "application/json"
    assert message["properties"].type == "wireless-network"
    payload = json.loads(message["body"].decode("utf-8"))
    assert payload["_id"] == network_document()["_id"]


def test_publish_retries_transient_failures() -> None:
    channel = FakeChannel(failures=2)
    publisher = _publisher(channel)
    routing_key = publisher.publish(network_document())
    assert routing_key == "documents.ingest.wireless-network"
    assert len(channel.published) == 1


def test_publish_gives_up_after_retries() -> None:
    channel = FakeChannel(failures=99)
    publisher = _publisher(channel)
    with pytest.raises(NetworkContractError, match="publish failed after 3 attempts"):
        publisher.publish(network_document())


def test_publish_rejects_invalid_document_before_broker() -> None:
    channel = FakeChannel()
    publisher = _publisher(channel)
    document = network_document()
    document["data"]["bssid"] = 42  # type violation
    with pytest.raises(NetworkContractError):
        publisher.publish(document)
    assert channel.published == []


def test_republish_is_idempotent_by_deterministic_id() -> None:
    channel = FakeChannel()
    publisher = _publisher(channel)
    publisher.publish(network_document())
    publisher.publish(network_document())
    assert len(channel.published) == 2
    first = json.loads(channel.published[0]["body"].decode("utf-8"))
    second = json.loads(channel.published[1]["body"].decode("utf-8"))
    assert first["_id"] == second["_id"]  # at-least-once + deterministic ids dedupe downstream
