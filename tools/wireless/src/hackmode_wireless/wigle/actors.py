"""WiGLE actor system: search actor + sink over the shared actor runtime."""

from __future__ import annotations

from collections.abc import Awaitable, Iterable, Mapping
from dataclasses import dataclass
from typing import Any, Callable, Protocol
from urllib.parse import urlencode

from hackmode_wireless.actor import Actor, ActorRef, ActorSystem
from hackmode_wireless.transport import Document
from hackmode_wireless.wigle.client import WigleClient, WigleSearch
from hackmode_wireless.wigle.mapping import DEFAULT_DATASET, host_document, network_document

DocumentHandler = Callable[[Document], Awaitable[None]]


@dataclass(frozen=True, slots=True)
class EmitDocument:
    document: Document


@dataclass(frozen=True, slots=True)
class SearchWigle:
    """Run one WiGLE network search and emit wireless-network documents."""

    search: WigleSearch
    dataset: str = DEFAULT_DATASET
    emit_hosts: bool = False


class WigleBackend(Protocol):
    def search(self, search: WigleSearch) -> Iterable[Mapping[str, Any]]: ...


class WigleSinkActor(Actor):
    def __init__(self, system: ActorSystem, handler: DocumentHandler) -> None:
        super().__init__("wigle-sink", system)
        self.handler = handler

    async def receive(self, message: object) -> None:
        if not isinstance(message, EmitDocument):
            raise TypeError(f"unsupported sink message: {type(message).__name__}")
        await self.handler(message.document)


class WigleActor(Actor):
    def __init__(self, system: ActorSystem, backend: WigleBackend, sink: ActorRef) -> None:
        super().__init__("wigle", system)
        self.backend = backend
        self.sink = sink

    async def receive(self, message: object) -> None:
        if isinstance(message, SearchWigle):
            await self._search(message)
        else:
            raise TypeError(f"unsupported wigle message: {type(message).__name__}")

    async def _search(self, message: SearchWigle) -> None:
        query = urlencode(
            {key: value for key, value in message.search.initial_params().items() if value is not None}
        )
        for result in self.backend.search(message.search):
            document = network_document(
                dict(result),
                dataset=message.dataset,
                query=query,
            )
            if message.emit_hosts:
                host = host_document(document, dataset=message.dataset)
                await self.sink.tell(EmitDocument(host))
            await self.sink.tell(EmitDocument(document))


def search_params_from_target(data: Mapping[str, Any]) -> SearchWigle:
    """Build a SearchWigle from a StarIntel ``target`` document's data.

    Recognized option entries (``data.options`` list of ``{"key", ...}``
    records or plain ``{"bbox": ...}`` maps) and direct ``data.query`` JSON:
    ``bbox`` ("lat1,lon1,lat2,lon2"), ``ssid``, ``netid``, ``onlymine``,
    ``max_pages``, ``emit_hosts``, ``dataset``.
    """
    values: dict[str, Any] = {}
    options = data.get("options")
    if isinstance(options, list):
        for option in options:
            if not isinstance(option, dict):
                continue
            key = option.get("key")
            if isinstance(key, str) and "value" in option:
                values[key] = option.get("value")
            else:
                values.update(
                    {str(name): value for name, value in option.items() if name != "key"}
                )
    query = data.get("query")
    if isinstance(query, str) and query.strip():
        import json

        try:
            parsed = json.loads(query)
        except json.JSONDecodeError:
            parsed = None
        if isinstance(parsed, dict):
            values.update(parsed)
    elif isinstance(query, dict):
        values.update(query)

    bbox = values.get("bbox")
    latrange1 = latrange2 = longrange1 = longrange2 = None
    if isinstance(bbox, str) and bbox.strip():
        parts = [part.strip() for part in bbox.split(",")]
        if len(parts) != 4:
            raise ValueError("bbox must be 'lat1,lon1,lat2,lon2'")
        numbers = [float(part) for part in parts]
        latrange1, latrange2 = min(numbers[0], numbers[2]), max(numbers[0], numbers[2])
        longrange1, longrange2 = min(numbers[1], numbers[3]), max(numbers[1], numbers[3])

    ssid = values.get("ssid")
    netid = values.get("netid")
    onlymine = bool(values.get("onlymine", False))
    max_pages = int(values.get("max_pages", 10))
    emit_hosts = bool(values.get("emit_hosts", False))
    dataset = str(values.get("dataset", DEFAULT_DATASET))
    return SearchWigle(
        search=WigleSearch(
            latrange1=latrange1,
            latrange2=latrange2,
            longrange1=longrange1,
            longrange2=longrange2,
            ssid=str(ssid) if ssid else None,
            netid=str(netid) if netid else None,
            onlymine=onlymine,
            max_pages=max_pages,
        ),
        dataset=dataset,
        emit_hosts=emit_hosts,
    )


class WigleActorSystem:
    """WiGLE actor system facade; documents are delivered to ``handler``."""

    def __init__(self, handler: DocumentHandler, backend: WigleBackend | None = None) -> None:
        self.system = ActorSystem()
        selected: WigleBackend = backend or _default_backend()
        sink = self.system.register(WigleSinkActor(self.system, handler))
        self.sink = sink
        self.wigle = self.system.register(WigleActor(self.system, selected, sink))

    async def start(self) -> None:
        await self.system.start()

    async def search(self, target: SearchWigle) -> None:
        await self._run(target)

    async def run_target(self, data: Mapping[str, Any]) -> None:
        await self._run(search_params_from_target(data))

    async def _run(self, target: object) -> None:
        await self.wigle.tell(target)
        await self.wigle.join()
        await self.sink.join()
        if not self.system.failures.empty():
            failure = self.system.failures.get_nowait()
            self.system.failures.task_done()
            raise RuntimeError(
                f"actor {failure.actor} failed handling {failure.message_type}: {failure.error}"
            )

    async def stop(self) -> None:
        await self.system.stop()


def _default_backend() -> WigleBackend:
    import os

    api_name = os.environ.get("STARINTEL_WIGLE_API_NAME", "")
    api_token = os.environ.get("STARINTEL_WIGLE_API_TOKEN", "")
    base_url = os.environ.get("STARINTEL_WIGLE_BASE_URL") or None
    if base_url:
        return WigleClient(api_name, api_token, base_url=base_url)
    return WigleClient(api_name, api_token)
