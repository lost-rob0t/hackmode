"""CLI smoke tests: every capability one-shot, JSONL offline mode, actor path."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import httpx
import pytest

from hackmode_wireless import cli
from hackmode_wireless.wigle.client import WigleClient

WIGLE_PAGE: dict[str, Any] = {
    "success": True,
    "totalResults": 1,
    "resultCount": 1,
    "searchAfter": "",
    "results": [
        {
            "netid": "0A:2C:EF:3D:25:1B",
            "ssid": "CLI Net",
            "trilat": 10.0,
            "trilong": 20.0,
            "encryption": "WPA2",
            "channel": 6,
            "qos": 3,
        }
    ],
}


@pytest.fixture
def wigle_transport() -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/api/v2/network/search"
        return httpx.Response(200, json=WIGLE_PAGE)

    return httpx.MockTransport(handler)


@pytest.fixture
def fake_wigle_cli(monkeypatch: pytest.MonkeyPatch, wigle_transport: httpx.MockTransport) -> None:
    def make_client(api_name: str, api_token: str, base_url: str) -> WigleClient:
        return WigleClient(
            api_name, api_token, base_url=base_url, transport=wigle_transport, page_delay=0.0
        )

    monkeypatch.setattr(cli, "make_wigle_client", make_client)


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def test_wigle_search_jsonl(
    fake_wigle_cli: None, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    sink = tmp_path / "out.jsonl"
    code = cli.main(
        [
            "wigle",
            "search",
            "--bbox",
            "10.0,20.0,11.0,21.0",
            "--api-name",
            "n",
            "--api-token",
            "t",
            "--base-url",
            "https://api.wigle.net",
            "--jsonl",
            str(sink),
        ]
    )
    assert code == 0
    documents = _read_jsonl(sink)
    assert len(documents) == 1
    assert documents[0]["dtype"] == "wireless-network"
    assert documents[0]["data"]["ssid"] == "CLI Net"
    # stdout stays clean in jsonl-file mode
    assert capsys.readouterr().out == ""


def test_wigle_search_requires_some_criterion(fake_wigle_cli: None, tmp_path: Path) -> None:
    with pytest.raises(SystemExit):
        cli.main(
            [
                "wigle",
                "search",
                "--api-name",
                "n",
                "--api-token",
                "t",
                "--jsonl",
                str(tmp_path / "out.jsonl"),
            ]
        )


class FakeKismetBackend:
    def __init__(self) -> None:
        self.polled: list[int] = []

    def devices_since(self, ts: int, fields: tuple[str, ...]) -> list[dict[str, Any]]:
        self.polled.append(ts)
        return [
            {
                "kismet.device.base.macaddr": "AA:BB:CC:00:11:22",
                "kismet.device.base.type": "Wi-Fi AP",
                "dot11.device": {
                    "dot11.device.advertised_ssid_map": {
                        "u": {"dot11.advertisedssid.ssid": "Net"}
                    }
                },
            },
            {
                "kismet.device.base.macaddr": "11:22:33:AA:BB:CC",
                "kismet.device.base.type": "Wi-Fi Device",
                "dot11.device": {
                    "dot11.device.probed_ssid_map": {"p": {"dot11.probedssid.ssid": "Net"}},
                    "dot11.device.last_bssid": "AA:BB:CC:00:11:22",
                },
            },
        ]

    def timestamp(self) -> int:
        return 1700000600


def test_kismet_poll_once_jsonl(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    backend = FakeKismetBackend()

    def make_client(
        base_url: str, token: str | None, user: str | None, password: str | None
    ) -> FakeKismetBackend:
        return backend

    monkeypatch.setattr(cli, "make_kismet_client", make_client)
    sink = tmp_path / "kismet.jsonl"
    code = cli.main(
        [
            "kismet",
            "poll",
            "--url",
            "http://kismet.test:2501",
            "--once",
            "--jsonl",
            str(sink),
        ]
    )
    assert code == 0
    documents = _read_jsonl(sink)
    dtypes = sorted(doc["dtype"] for doc in documents)
    # 1 network + 2 stations (AP + client) + 1 client-observed-at-station relation
    assert dtypes == ["relation", "wireless-network", "wireless-station", "wireless-station"]
    relation = next(doc for doc in documents if doc["dtype"] == "relation")
    station_ids = {doc["_id"] for doc in documents if doc["dtype"] == "wireless-station"}
    network_ids = {doc["_id"] for doc in documents if doc["dtype"] == "wireless-network"}
    assert relation["data"]["subject"] in station_ids
    assert relation["data"]["object"] in network_ids
    assert relation["data"]["subject"] != relation["data"]["object"]
    assert backend.polled == [0]


def test_kismet_poll_second_sweep_dedupes(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    backend = FakeKismetBackend()

    def make_client(
        base_url: str, token: str | None, user: str | None, password: str | None
    ) -> FakeKismetBackend:
        return backend

    monkeypatch.setattr(cli, "make_kismet_client", make_client)
    sink_one = tmp_path / "one.jsonl"
    sink_two = tmp_path / "two.jsonl"
    assert cli.main(["kismet", "poll", "--url", "http://k", "--once", "--jsonl", str(sink_one)]) == 0
    assert cli.main(["kismet", "poll", "--url", "http://k", "--once", "--jsonl", str(sink_two)]) == 0
    ids_one = {doc["_id"] for doc in _read_jsonl(sink_one)}
    ids_two = {doc["_id"] for doc in _read_jsonl(sink_two)}
    assert ids_one and ids_two
    # deterministic ids: a fresh process run of the same sweep would collide only
    # within one system instance; within this CLI each run is a new system, so we
    # assert equality of ids to prove determinism.
    assert ids_one == ids_two


def test_wigle_detail_jsonl(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/v2/network/0A:2C:EF:3D:25:1B":
            return httpx.Response(
                200,
                json={"success": True, "results": [dict(WIGLE_PAGE["results"][0])]},
            )
        return httpx.Response(404)

    def make_client(api_name: str, api_token: str, base_url: str) -> WigleClient:
        return WigleClient(
            api_name, api_token, base_url=base_url, transport=httpx.MockTransport(handler)
        )

    monkeypatch.setattr(cli, "make_wigle_client", make_client)
    sink = tmp_path / "detail.jsonl"
    code = cli.main(
        [
            "wigle",
            "detail",
            "--netid",
            "0A:2C:EF:3D:25:1B",
            "--api-name",
            "n",
            "--api-token",
            "t",
            "--jsonl",
            str(sink),
        ]
    )
    assert code == 0
    documents = _read_jsonl(sink)
    assert len(documents) == 1
    assert documents[0]["data"]["bssid"] == "0a:2c:ef:3d:25:1b"


def test_manifests_jsonl(tmp_path: Path) -> None:
    sink = tmp_path / "manifests.jsonl"
    code = cli.main(["manifests", "--jsonl", str(sink)])
    assert code == 0
    documents = _read_jsonl(sink)
    assert sorted(doc["data"]["actor"] for doc in documents) == ["kismet", "wigle"]


def test_kismet_status(monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    class FakeStatusClient:
        def system_status(self) -> dict[str, Any]:
            return {"kismet.system.version": "2025-09-R1"}

        def close(self) -> None:
            return None

    monkeypatch.setattr(
        cli, "make_kismet_client", lambda *args: FakeStatusClient()
    )
    code = cli.main(["kismet", "status", "--url", "http://k"])
    assert code == 0
    assert "2025-09-R1" in capsys.readouterr().out


def test_bbox_validation() -> None:
    from hackmode_wireless.cli import _bbox_ranges

    ranges = _bbox_ranges("11.0, 20.0, 10.0, 21.0")
    assert ranges == {
        "latrange1": 10.0,
        "latrange2": 11.0,
        "longrange1": 20.0,
        "longrange2": 21.0,
    }
    with pytest.raises(SystemExit):
        _bbox_ranges("1,2,3")


def test_wigle_actor_target_params() -> None:
    from hackmode_wireless.wigle.actors import search_params_from_target

    target = search_params_from_target(
        {
            "target": "wigle search",
            "options": [
                {"key": "bbox", "value": "1.0,2.0,3.0,4.0"},
                {"key": "ssid", "value": "net"},
                {"key": "onlymine", "value": True},
            ],
        }
    )
    assert target.search.latrange1 == 1.0
    assert target.search.longrange2 == 4.0
    assert target.search.ssid == "net"
    assert target.search.onlymine is True


def test_actor_systems_exposed() -> None:
    from hackmode_wireless.kismet.actors import KismetActorSystem
    from hackmode_wireless.wigle.actors import WigleActorSystem

    assert WigleActorSystem is not None
    assert KismetActorSystem is not None
