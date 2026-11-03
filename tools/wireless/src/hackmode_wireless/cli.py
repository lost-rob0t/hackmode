"""``hm-wireless`` console entry point.

Every actor capability is also runnable as a one-shot CLI tool that builds
the same documents and validates/publishes them through the same transport
(RabbitMQ by default, ``--jsonl`` for the offline sink).  This dual
actor+CLI form is a repo invariant (see README.md).
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
from collections.abc import Awaitable, Callable
from typing import Any

from hackmode_wireless.kismet.actors import KismetActorSystem, KismetPollConfig
from hackmode_wireless.kismet.client import DEFAULT_BASE_URL as KISMET_DEFAULT_URL
from hackmode_wireless.transport import (
    Document,
    SchemaBoundary,
    ValidatingPublisher,
    transport_from_env,
)
from hackmode_wireless.wigle.actors import SearchWigle, WigleActorSystem
from hackmode_wireless.wigle.client import BASE_URL as WIGLE_DEFAULT_URL
from hackmode_wireless.wigle.client import WigleClient
from hackmode_wireless.wigle.mapping import DEFAULT_DATASET as WIGLE_DATASET

LOGGER = logging.getLogger(__name__)


def make_wigle_client(api_name: str, api_token: str, base_url: str) -> WigleClient:
    """Client factory; monkeypatched by hermetic CLI tests."""
    return WigleClient(api_name, api_token, base_url=base_url)


def make_kismet_client(
    base_url: str, token: str | None, user: str | None, password: str | None
) -> Any:
    """Client factory; monkeypatched by hermetic CLI tests."""
    from hackmode_wireless.kismet.client import KismetClient

    return KismetClient(base_url, token=token, username=user, password=password)


def _handler(publisher: ValidatingPublisher) -> Callable[[Document], Awaitable[None]]:
    async def handle(document: Document) -> None:
        await asyncio.to_thread(publisher.publish, document)

    return handle


def _add_sink_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--jsonl", help="offline JSONL sink path instead of RabbitMQ")
    parser.add_argument("--rabbit-url", help="AMQP URL (default STARINTEL_RABBITMQ_URL)")
    parser.add_argument(
        "--dataset",
        default=None,
        help="dataset label (default STARINTEL_DATASET or the actor default)",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="hm-wireless",
        description="StarIntel wireless/network collection tools (WiGLE, Kismet).",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    wigle = sub.add_parser("wigle", help="WiGLE API v2 collection")
    wigle_sub = wigle.add_subparsers(dest="wigle_command", required=True)

    wigle_search = wigle_sub.add_parser("search", help="network/search by bbox/ssid/netid")
    wigle_search.add_argument(
        "--bbox", help="bounding box 'lat1,lon1,lat2,lon2' (latrange/longrange pair)"
    )
    wigle_search.add_argument("--ssid")
    wigle_search.add_argument("--netid", help="BSSID, first three octets minimum")
    wigle_search.add_argument("--onlymine", action="store_true")
    wigle_search.add_argument("--max-pages", type=int, default=10)
    wigle_search.add_argument("--emit-hosts", action="store_true")
    wigle_search.add_argument("--api-name", default=os.environ.get("STARINTEL_WIGLE_API_NAME", ""))
    wigle_search.add_argument(
        "--api-token", default=os.environ.get("STARINTEL_WIGLE_API_TOKEN", "")
    )
    wigle_search.add_argument("--base-url", default=os.environ.get("STARINTEL_WIGLE_BASE_URL", WIGLE_DEFAULT_URL))
    _add_sink_options(wigle_search)

    wigle_detail = wigle_sub.add_parser("detail", help="network detail for one BSSID")
    wigle_detail.add_argument("--netid", required=True)
    wigle_detail.add_argument("--api-name", default=os.environ.get("STARINTEL_WIGLE_API_NAME", ""))
    wigle_detail.add_argument(
        "--api-token", default=os.environ.get("STARINTEL_WIGLE_API_TOKEN", "")
    )
    wigle_detail.add_argument("--base-url", default=os.environ.get("STARINTEL_WIGLE_BASE_URL", WIGLE_DEFAULT_URL))
    _add_sink_options(wigle_detail)

    wigle_bt = wigle_sub.add_parser("bluetooth", help="bluetooth/search")
    wigle_bt.add_argument("--bbox")
    wigle_bt.add_argument("--name")
    wigle_bt.add_argument("--namelike")
    wigle_bt.add_argument("--max-pages", type=int, default=10)
    wigle_bt.add_argument("--api-name", default=os.environ.get("STARINTEL_WIGLE_API_NAME", ""))
    wigle_bt.add_argument(
        "--api-token", default=os.environ.get("STARINTEL_WIGLE_API_TOKEN", "")
    )
    wigle_bt.add_argument("--base-url", default=os.environ.get("STARINTEL_WIGLE_BASE_URL", WIGLE_DEFAULT_URL))
    _add_sink_options(wigle_bt)

    kismet = sub.add_parser("kismet", help="Kismet REST collection")
    kismet_sub = kismet.add_subparsers(dest="kismet_command", required=True)

    kismet_poll = kismet_sub.add_parser("poll", help="poll devices since last timestamp")
    kismet_poll.add_argument("--url", default=os.environ.get("STARINTEL_KISMET_URL", KISMET_DEFAULT_URL))
    kismet_poll.add_argument("--interval", type=float, default=30.0)
    kismet_poll.add_argument(
        "--once", action="store_true", help="run a single poll sweep and exit"
    )
    kismet_poll.add_argument("--token", default=os.environ.get("KISMET_TOKEN"))
    kismet_poll.add_argument("--user", default=os.environ.get("KISMET_USER"))
    kismet_poll.add_argument("--password", default=os.environ.get("KISMET_PASSWORD"))
    _add_sink_options(kismet_poll)

    kismet_status = kismet_sub.add_parser("status", help="probe /system/status.readonly")
    kismet_status.add_argument("--url", default=os.environ.get("STARINTEL_KISMET_URL", KISMET_DEFAULT_URL))
    kismet_status.add_argument("--token", default=os.environ.get("KISMET_TOKEN"))
    kismet_status.add_argument("--user", default=os.environ.get("KISMET_USER"))
    kismet_status.add_argument("--password", default=os.environ.get("KISMET_PASSWORD"))

    manifests = sub.add_parser("manifests", help="emit actor-manifest documents")
    manifests.add_argument("--actor", action="append", default=[])
    manifests.add_argument("--jsonl")

    return parser


def _bbox_ranges(bbox: str | None) -> dict[str, Any]:
    if not bbox:
        return {}
    parts = [part.strip() for part in bbox.split(",")]
    if len(parts) != 4:
        raise SystemExit("--bbox must be 'lat1,lon1,lat2,lon2'")
    numbers = [float(part) for part in parts]
    return {
        "latrange1": min(numbers[0], numbers[2]),
        "latrange2": max(numbers[0], numbers[2]),
        "longrange1": min(numbers[1], numbers[3]),
        "longrange2": max(numbers[1], numbers[3]),
    }


def _publisher(args: argparse.Namespace, boundary: SchemaBoundary) -> ValidatingPublisher:
    return transport_from_env(
        boundary,
        jsonl_path=getattr(args, "jsonl", None),
        rabbit_url=getattr(args, "rabbit_url", None),
    )


async def _wigle_search(args: argparse.Namespace, publisher: ValidatingPublisher) -> int:
    from hackmode_wireless.wigle.client import WigleSearch as _WigleSearch

    ranges = _bbox_ranges(args.bbox)
    if not ranges and not args.ssid and not args.netid:
        raise SystemExit("wigle search requires --bbox, --ssid, or --netid")
    search = _WigleSearch(
        ssid=args.ssid,
        netid=args.netid,
        onlymine=args.onlymine,
        max_pages=args.max_pages,
        **ranges,
    )
    client = make_wigle_client(args.api_name, args.api_token, args.base_url)
    system = WigleActorSystem(_handler(publisher), backend=client)
    await system.start()
    try:
        await system.search(
            SearchWigle(
                search=search,
                dataset=args.dataset or os.environ.get("STARINTEL_DATASET", WIGLE_DATASET),
                emit_hosts=args.emit_hosts,
            )
        )
    finally:
        await system.stop()
    return 0


async def _wigle_bluetooth(args: argparse.Namespace, publisher: ValidatingPublisher) -> int:
    from hackmode_wireless.wigle.client import WigleBluetoothSearch
    from hackmode_wireless.wigle.mapping import network_document

    ranges = _bbox_ranges(args.bbox)
    search = WigleBluetoothSearch(
        name=args.name,
        namelike=args.namelike,
        max_pages=args.max_pages,
        **ranges,
    )
    client = make_wigle_client(args.api_name, args.api_token, args.base_url)
    try:
        for result in client.bluetooth_search(search):
            publisher.publish(network_document(dict(result), dataset=args.dataset or "wigle-bt"))
    finally:
        client.close()
    return 0


def _wigle_detail(args: argparse.Namespace, publisher: ValidatingPublisher) -> int:
    from hackmode_wireless.wigle.mapping import network_document

    client = make_wigle_client(args.api_name, args.api_token, args.base_url)
    try:
        payload = client.network_detail(args.netid)
    finally:
        client.close()
    results = payload.get("results") or []
    groups = payload.get("groups") or []
    count = 0
    for result in [*results, *groups]:
        if isinstance(result, dict) and result.get("netid"):
            publisher.publish(network_document(result, dataset=args.dataset or "wigle"))
            count += 1
    print(f"published {count} documents for {args.netid}")
    return 0


async def _kismet_poll(args: argparse.Namespace, publisher: ValidatingPublisher) -> int:
    from urllib.parse import urlparse

    host = urlparse(args.url).netloc or args.url
    config = KismetPollConfig(
        base_url=args.url,
        source_device_id=f"kismet:{host}",
        dataset=args.dataset or os.environ.get("STARINTEL_DATASET", "kismet"),
        poll_interval=args.interval,
    )
    client = make_kismet_client(args.url, args.token, args.user, args.password)
    system = KismetActorSystem(_handler(publisher), backend=client, config=config)
    await system.start()
    try:
        if args.once:
            await system.poll_once()
        else:
            await system.run_forever()
    except (KeyboardInterrupt, asyncio.CancelledError):
        pass
    finally:
        await system.stop()
    return 0


def _kismet_status(args: argparse.Namespace) -> int:
    client = make_kismet_client(args.url, args.token, args.user, args.password)
    try:
        status = client.system_status()
    finally:
        client.close()
    import json

    print(json.dumps(status, sort_keys=True))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    boundary = SchemaBoundary.default()

    if args.command == "manifests":
        from hackmode_wireless.manifests import _selected_documents

        documents = _selected_documents(args.actor, None)
        sink = transport_from_env(boundary, jsonl_path=args.jsonl)
        count = sink.publish_all(documents)
        sink.close()
        print(f"published {count} manifest documents")
        return 0

    publisher = _publisher(args, boundary)
    try:
        if args.command == "wigle":
            if args.wigle_command == "search":
                return asyncio.run(_wigle_search(args, publisher))
            if args.wigle_command == "detail":
                return _wigle_detail(args, publisher)
            if args.wigle_command == "bluetooth":
                return asyncio.run(_wigle_bluetooth(args, publisher))
        elif args.command == "kismet":
            if args.kismet_command == "poll":
                return asyncio.run(_kismet_poll(args, publisher))
            if args.kismet_command == "status":
                return _kismet_status(args)
        parser.error(f"unknown command: {args.command}")
    finally:
        publisher.close()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
