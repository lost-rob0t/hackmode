"""Asyncio actor lifecycle mirroring ``starintel_pro_actors.actor``.

Ported from starintel-pro-actors so hackmode-wireless actors are drop-in
familiar: Pykka owns delivery, async backends stay on their owning event
loop, and ``ActorSystem.start()`` publishes actor-manifest documents when a
RabbitMQ URL is configured.
"""

from __future__ import annotations

import asyncio
import logging
import os
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import StrEnum

import pykka

from hackmode_wireless.transport import rabbit_url_from_env

LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class Stop:
    """Stop an actor after all earlier mailbox messages are processed."""


@dataclass(frozen=True, slots=True)
class ActorFailure:
    actor: str
    message_type: str
    error: str


class ActorState(StrEnum):
    NEW = "new"
    STARTING = "starting"
    RUNNING = "running"
    STOPPING = "stopping"
    STOPPED = "stopped"


class _MailboxActor(pykka.ThreadingActor):
    """Pykka owns delivery; async backends stay on their owning event loop."""

    def __init__(self, owner: Actor, loop: asyncio.AbstractEventLoop) -> None:
        super().__init__()
        self.owner = owner
        self.loop = loop

    def on_receive(self, message: object) -> None:
        asyncio.run_coroutine_threadsafe(self.owner._deliver(message), self.loop).result()

    def on_stop(self) -> None:
        try:
            self.loop.call_soon_threadsafe(self.owner._on_pykka_stopped)
        except RuntimeError:
            LOGGER.exception("actor %s stopped after its event loop closed", self.owner.name)


class ActorRef:
    def __init__(self, actor: Actor, capacity: int) -> None:
        if capacity <= 0:
            raise ValueError("mailbox_size must be positive")
        self.name = actor.name
        self._actor = actor
        self._capacity = capacity
        self._pending = 0
        self._idle = asyncio.Event()
        self._idle.set()
        self._space = asyncio.Event()
        self._space.set()

    async def tell(self, message: object) -> None:
        if isinstance(message, Stop):
            self.tell_nowait(message)
            return
        while self._pending >= self._capacity:
            if not self._actor._accepting:
                raise pykka.ActorDeadError(f"actor is stopping: {self.name}")
            await self._space.wait()
        self.tell_nowait(message)

    def tell_nowait(self, message: object) -> None:
        worker = self._actor._worker
        if worker is None or not self._actor._accepting:
            raise pykka.ActorDeadError(f"actor is not accepting messages: {self.name}")
        if asyncio.get_running_loop() is not self._actor._loop:
            raise RuntimeError("async actor references must use their owning event loop")
        if isinstance(message, Stop):
            self._actor.request_stop()
            return
        if self._pending >= self._capacity:
            raise asyncio.QueueFull
        worker.tell(message)
        self._pending += 1
        self._idle.clear()
        if self._pending >= self._capacity:
            self._space.clear()

    def _completed(self) -> None:
        self._pending -= 1
        assert self._pending >= 0
        self._space.set()
        if self._pending == 0:
            self._idle.set()

    async def join(self) -> None:
        await self._idle.wait()

    @property
    def pending(self) -> int:
        return self._pending


class Actor(ABC):
    def __init__(self, name: str, system: ActorSystem, mailbox_size: int = 1_000) -> None:
        self.name = name
        self.system = system
        self.ref = ActorRef(self, mailbox_size)
        self._worker: pykka.ActorRef[_MailboxActor] | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._accepting = False
        self._lifecycle_state = ActorState.NEW
        self._stopped = asyncio.Event()
        self._stopped.set()
        self._stop_error: BaseException | None = None
        self._finish_task: asyncio.Task[None] | None = None
        self._cleanup_started = False
        self._delivery_task: asyncio.Task[None] | None = None

    @property
    def lifecycle_state(self) -> ActorState:
        return self._lifecycle_state

    async def start(self) -> None:
        if self._worker is not None or self._lifecycle_state in {ActorState.STARTING, ActorState.RUNNING}:
            raise RuntimeError(f"actor already started: {self.name}")
        self._loop = asyncio.get_running_loop()
        self._lifecycle_state = ActorState.STARTING
        self._stopped.clear()
        self._stop_error = None
        self._finish_task = None
        self._cleanup_started = False
        try:
            await self.pre_start()
            self._worker = _MailboxActor.start(self, self._loop)
        except BaseException:
            self._accepting = False
            self._lifecycle_state = ActorState.STOPPING
            await self._finish_stop()
            raise
        self._lifecycle_state = ActorState.RUNNING
        self._accepting = True

    def request_stop(self) -> None:
        """Request a graceful Pykka stop without waiting for the actor itself."""

        worker = self._worker
        if worker is None:
            if self._lifecycle_state in {ActorState.STOPPING, ActorState.STOPPED}:
                return
            raise pykka.ActorDeadError(f"actor is not running: {self.name}")
        if asyncio.get_running_loop() is not self._loop:
            raise RuntimeError("actor lifecycle must use its owning event loop")
        if self._lifecycle_state in {ActorState.STOPPING, ActorState.STOPPED}:
            return
        if self._lifecycle_state is not ActorState.RUNNING:
            raise RuntimeError(f"actor cannot stop from state {self._lifecycle_state.value}: {self.name}")

        self._lifecycle_state = ActorState.STOPPING
        self._accepting = False
        self.ref._space.set()
        worker.stop(block=False)

    async def stop(self) -> None:
        if self._worker is None:
            if self._lifecycle_state is ActorState.STOPPING:
                await self._stopped.wait()
            if self._stop_error is not None:
                raise self._stop_error
            return

        self.request_stop()

        # Waiting for Pykka termination from inside the current receive would
        # deadlock; in that context stop() means request stop.
        if asyncio.current_task() is self._delivery_task:
            return

        await self._stopped.wait()
        if self._stop_error is not None:
            raise self._stop_error

    def _on_pykka_stopped(self) -> None:
        """Run on the owning asyncio loop after Pykka invokes ``on_stop``."""

        self._accepting = False
        self.ref._space.set()
        if self._lifecycle_state is not ActorState.STOPPED:
            self._lifecycle_state = ActorState.STOPPING
        if self._finish_task is None:
            self._finish_task = asyncio.create_task(
                self._finish_stop(), name=f"finish-stop:{self.name}"
            )

    async def _finish_stop(self) -> None:
        if self._cleanup_started:
            return
        self._cleanup_started = True
        self._worker = None
        try:
            await self.post_stop()
        except BaseException as exc:
            self._stop_error = exc
            LOGGER.exception("actor %s failed during post_stop", self.name)
        finally:
            self._accepting = False
            self._lifecycle_state = ActorState.STOPPED
            self.ref._space.set()
            self._stopped.set()

    async def _deliver(self, message: object) -> None:
        delivery_task = asyncio.current_task()
        if delivery_task is None:
            raise RuntimeError("actor delivery requires an asyncio task")
        self._delivery_task = delivery_task
        try:
            await self.receive(message)
        except Exception as exc:
            LOGGER.exception("actor %s failed handling %s", self.name, type(message).__name__)
            await self.system.report_failure(self, message, exc)
            try:
                await self.on_error(message, exc)
            except Exception as hook_error:
                await self.system.report_failure(self, message, hook_error)
        finally:
            self._delivery_task = None
            self.ref._completed()

    async def pre_start(self) -> None:
        pass

    async def post_stop(self) -> None:
        pass

    async def on_error(self, message: object, error: Exception) -> None:
        pass

    @abstractmethod
    async def receive(self, message: object) -> None:
        raise NotImplementedError


class ActorSystem:
    def __init__(self) -> None:
        self._actors: dict[str, Actor] = {}
        self.failures: asyncio.Queue[ActorFailure] = asyncio.Queue()

    def register(self, actor: Actor) -> ActorRef:
        if actor.name in self._actors:
            raise ValueError(f"duplicate actor name: {actor.name}")
        self._actors[actor.name] = actor
        return actor.ref

    def ref(self, name: str) -> ActorRef:
        try:
            return self._actors[name].ref
        except KeyError as exc:
            raise KeyError(f"unknown actor: {name}") from exc

    async def start(self) -> None:
        await self._publish_actor_manifests()
        started: list[Actor] = []
        try:
            for actor in self._actors.values():
                await actor.start()
                started.append(actor)
        except BaseException:
            for actor in reversed(started):
                await actor.stop()
            raise

    async def _publish_actor_manifests(self) -> None:
        url = rabbit_url_from_env()
        if not url:
            return

        from hackmode_wireless.manifests import (
            actor_manifest_document,
            manifest_ids_for_actor_names,
            publish_actor_manifests,
        )

        actor_ids = manifest_ids_for_actor_names(self._actors)
        if not actor_ids:
            return
        documents = tuple(actor_manifest_document(actor_id) for actor_id in actor_ids)
        exchange = os.environ.get("STARINTEL_RABBITMQ_EXCHANGE") or os.environ.get(
            "STARINTEL_RABBIT_EXCHANGE", "documents"
        )
        await asyncio.to_thread(publish_actor_manifests, documents, url, exchange=exchange)

    async def join(self) -> None:
        await asyncio.gather(*(actor.ref.join() for actor in self._actors.values()))

    async def stop(self) -> None:
        for actor in reversed(tuple(self._actors)):
            await self._actors[actor].stop()

    async def report_failure(self, actor: Actor, message: object, error: Exception) -> None:
        await self.failures.put(
            ActorFailure(
                actor=actor.name,
                message_type=type(message).__name__,
                error=f"{type(error).__name__}: {error}",
            )
        )

    @property
    def pending(self) -> int:
        return sum(actor.ref.pending for actor in self._actors.values())

    def actor_names(self) -> tuple[str, ...]:
        return tuple(self._actors)
