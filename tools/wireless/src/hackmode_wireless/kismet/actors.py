"""Kismet actor system: timestamp-delta poller + sink."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any, Protocol

from hackmode_wireless.actor import Actor, ActorRef, ActorSystem
from hackmode_wireless.kismet.client import KISMET_DEVICE_FIELDS, KismetClient
from hackmode_wireless.kismet.mapping import (
    DEFAULT_DATASET,
    network_documents,
    observed_at_station_relations,
    station_document,
)
from hackmode_wireless.transport import Document

LOGGER = logging.getLogger(__name__)

DocumentHandler = Callable[[Document], Awaitable[None]]


@dataclass(frozen=True, slots=True)
class EmitDocument:
    document: Document


@dataclass(frozen=True, slots=True)
class PollOnce:
    """Poll devices modified since the last cursor and emit the delta."""


@dataclass(frozen=True, slots=True)
class KismetPollConfig:
    base_url: str = "http://127.0.0.1:2501"
    source_device_id: str = "kismet"
    dataset: str = DEFAULT_DATASET
    poll_interval: float = 30.0
    fields: tuple[str, ...] = KISMET_DEVICE_FIELDS


@dataclass
class _PollState:
    cursor: int = 0
    seen: set[str] = field(default_factory=set)


class KismetBackend(Protocol):
    def devices_since(self, ts: int, fields: tuple[str, ...]) -> list[dict[str, Any]]: ...

    def timestamp(self) -> int: ...


class KismetSinkActor(Actor):
    def __init__(self, system: ActorSystem, handler: DocumentHandler) -> None:
        super().__init__("kismet-sink", system)
        self.handler = handler

    async def receive(self, message: object) -> None:
        if not isinstance(message, EmitDocument):
            raise TypeError(f"unsupported sink message: {type(message).__name__}")
        await self.handler(message.document)


class KismetPollerActor(Actor):
    """Poll the Kismet REST API and emit new/changed documents by _id."""

    def __init__(
        self,
        system: ActorSystem,
        backend: KismetBackend,
        sink: ActorRef,
        config: KismetPollConfig,
    ) -> None:
        super().__init__("kismet", system)
        self.backend = backend
        self.sink = sink
        self.config = config
        self.state = _PollState()

    async def receive(self, message: object) -> None:
        if isinstance(message, PollOnce):
            await self._poll_once()
        else:
            raise TypeError(f"unsupported kismet message: {type(message).__name__}")

    async def _poll_once(self) -> None:
        devices = await asyncio.to_thread(
            self.backend.devices_since, self.state.cursor, self.config.fields
        )
        cursor = await asyncio.to_thread(self.backend.timestamp)
        networks_by_bssid: dict[str, list[Document]] = {}
        stations: list[tuple[Document, str]] = []
        for device in devices:
            networks = network_documents(
                device,
                base_url=self.config.base_url,
                source_device_id=self.config.source_device_id,
                dataset=self.config.dataset,
            )
            station = station_document(
                device,
                base_url=self.config.base_url,
                source_device_id=self.config.source_device_id,
                dataset=self.config.dataset,
            )
            if station is not None:
                stations.append((station, str(station["data"].get("last_bssid") or "")))
                await self._emit_new(station)
            for network in networks:
                networks_by_bssid.setdefault(str(network["data"]["bssid"]), []).append(network)
                await self._emit_new(network)
        # "observed_at_station": a client station observed at an AP's network,
        # keyed by the client's last associated BSSID.
        for station, last_bssid in stations:
            for network in networks_by_bssid.get(last_bssid, []):
                for relation in observed_at_station_relations(
                    station, [network], dataset=self.config.dataset
                ):
                    await self._emit_new(relation)
        self.state.cursor = cursor

    async def _emit_new(self, document: Document) -> None:
        if document["_id"] in self.state.seen:
            return
        self.state.seen.add(document["_id"])
        await self.sink.tell(EmitDocument(document))


class KismetActorSystem:
    """Kismet poller facade; documents are delivered to ``handler``."""

    def __init__(
        self,
        handler: DocumentHandler,
        backend: KismetBackend | None = None,
        config: KismetPollConfig | None = None,
    ) -> None:
        self.config = config or KismetPollConfig()
        self.system = ActorSystem()
        selected: KismetBackend = backend or KismetClient(
            self.config.base_url,
            token=_env("KISMET_TOKEN"),
            username=_env("KISMET_USER"),
            password=_env("KISMET_PASSWORD"),
        )
        sink = self.system.register(KismetSinkActor(self.system, handler))
        self.sink = sink
        self.kismet = self.system.register(
            KismetPollerActor(self.system, selected, sink, self.config)
        )

    async def start(self) -> None:
        await self.system.start()

    async def poll_once(self) -> None:
        await self._run(PollOnce())

    async def run_forever(self) -> None:
        while True:
            await self._run(PollOnce())
            await asyncio.sleep(self.config.poll_interval)

    async def _run(self, target: object) -> None:
        await self.kismet.tell(target)
        await self.kismet.join()
        await self.sink.join()
        if not self.system.failures.empty():
            failure = self.system.failures.get_nowait()
            self.system.failures.task_done()
            raise RuntimeError(
                f"actor {failure.actor} failed handling {failure.message_type}: {failure.error}"
            )

    async def stop(self) -> None:
        await self.system.stop()


def _env(name: str) -> str | None:
    import os

    return os.environ.get(name) or None
