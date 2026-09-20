"""Hermetic WiGLE client tests via httpx.MockTransport."""

from __future__ import annotations

import base64
import json
from typing import Any

import httpx
import pytest

from hackmode_wireless.wigle.client import (
    WigleBluetoothSearch,
    WigleClient,
    WigleError,
    WigleSearch,
)

SEARCH_BODY: dict[str, Any] = {
    "success": True,
    "totalResults": 2,
    "resultCount": 2,
    "searchAfter": "MTIz",
    "results": [
        {"netid": "00:11:22:33:44:55", "ssid": "alpha", "encryption": "WPA2", "channel": 6},
        {"netid": "00:11:22:33:44:66", "ssid": "beta", "encryption": "None", "channel": 11},
    ],
}


def _client(handler: Any) -> WigleClient:
    return WigleClient(
        "api-name",
        "api-token",
        base_url="https://api.wigle.net",
        transport=httpx.MockTransport(handler),
        page_delay=0.0,
    )


def test_search_sends_bbox_and_auth() -> None:
    calls: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        assert request.url.path == "/api/v2/network/search"
        return httpx.Response(200, json=SEARCH_BODY)

    with _client(handler) as client:
        results = list(
            client.search(
                WigleSearch(
                    latrange1=10.0, latrange2=11.0, longrange1=-5.0, longrange2=-4.0, ssid="alpha"
                )
            )
        )

    assert [item["netid"] for item in results] == ["00:11:22:33:44:55", "00:11:22:33:44:66"]
    request = calls[0]
    params = dict(request.url.params)
    assert params["latrange1"] == "10.0"
    assert params["latrange2"] == "11.0"
    assert params["longrange1"] == "-5.0"
    assert params["longrange2"] == "-4.0"
    assert params["ssid"] == "alpha"
    assert int(params["resultsPerPage"]) <= 100
    expected = base64.b64encode(b"api-name:api-token").decode()
    assert request.headers["authorization"] == f"Basic {expected}"


def test_search_paginates_with_searchafter() -> None:
    pages: list[dict[str, Any]] = [
        SEARCH_BODY,
        {
            "success": True,
            "totalResults": 2,
            "resultCount": 1,
            "searchAfter": "NDU2",
            "results": [{"netid": "00:11:22:33:44:77", "ssid": "gamma", "encryption": "WPA3"}],
        },
    ]
    queries: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        queries.append(str(request.url.params.get("searchafter", "")))
        return httpx.Response(200, json=pages[len(queries) - 1])

    with _client(handler) as client:
        results = list(client.search(WigleSearch(ssid="x", max_pages=5, results_per_page=2)))

    assert len(results) == 3
    assert queries == ["", "MTIz"]


def test_search_falls_back_to_lastnetid() -> None:
    body = dict(SEARCH_BODY)
    del body["searchAfter"]
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(str(request.url.params.get("lastnetid", "")))
        if len(seen) == 1:
            return httpx.Response(200, json=body)
        return httpx.Response(200, json={"success": True, "resultCount": 0, "results": []})

    with _client(handler) as client:
        results = list(client.search(WigleSearch(ssid="x", max_pages=5, results_per_page=2)))

    assert len(results) == 2
    assert seen == ["", "00:11:22:33:44:66"]


def test_search_stops_when_short_page() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=SEARCH_BODY)

    with _client(handler) as client:
        results = list(
            client.search(WigleSearch(ssid="x", results_per_page=100, max_pages=5))
        )

    assert len(results) == 2  # short page ends pagination


def test_search_raises_on_api_failure() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"success": False, "message": "quota exceeded"})

    with _client(handler) as client, pytest.raises(WigleError, match="quota exceeded"):
        list(client.search(WigleSearch(ssid="x")))


def test_search_raises_on_http_error() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(403, text="forbidden")

    with _client(handler) as client, pytest.raises(WigleError, match="HTTP 403"):
        list(client.search(WigleSearch(ssid="x")))


def test_network_detail_primary_path() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/api/v2/network/AA:BB:CC:DD:EE:FF"
        return httpx.Response(200, json={"success": True, "results": []})

    with _client(handler) as client:
        assert client.network_detail("AA:BB:CC:DD:EE:FF") == {"success": True, "results": []}


def test_network_detail_falls_back_to_query_form() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/v2/network/detail":
            assert request.url.params["netid"] == "AA:BB:CC:DD:EE:FF"
            return httpx.Response(200, json={"success": True})
        return httpx.Response(404, text="not found")

    with _client(handler) as client:
        payload = client.network_detail("AA:BB:CC:DD:EE:FF")
    assert payload == {"success": True}


def test_bluetooth_search_params() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/api/v2/bluetooth/search"
        return httpx.Response(200, json={"success": True, "resultCount": 0, "results": []})

    with _client(handler) as client:
        results = list(
            client.bluetooth_search(
                WigleBluetoothSearch(latrange1=1.0, latrange2=2.0, longrange1=3.0, longrange2=4.0, name="beat")
            )
        )
    assert results == []


def test_onlymine_flag_sent() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["onlymine"] == "true"
        return httpx.Response(200, json={"success": True, "resultCount": 0, "results": []})

    with _client(handler) as client:
        list(client.search(WigleSearch(onlymine=True)))


def test_missing_credentials_rejected() -> None:
    with pytest.raises(WigleError):
        WigleClient("", "")


def test_payload_json_shape() -> None:
    """The response envelope shape asserted above is the documented one."""

    body = json.dumps(SEARCH_BODY)
    assert "searchAfter" in body
    assert "netid" in body
