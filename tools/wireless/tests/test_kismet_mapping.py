"""Hermetic Kismet client + mapping tests."""

from __future__ import annotations

from typing import Any

import httpx
import pytest

from hackmode_wireless.kismet.client import KismetClient, KismetError
from hackmode_wireless.kismet.mapping import (
    OBSERVED_AT_STATION,
    advertised_ssids,
    field_path,
    network_documents,
    observed_at_station_relations,
    probe_ssids,
    station_document,
    station_type_from_device,
)
from hackmode_wireless.transport import SchemaBoundary

AP_DEVICE: dict[str, Any] = {
    "kismet.device.base.macaddr": "AA:BB:CC:00:11:22",
    "kismet.device.base.type": "Wi-Fi AP",
    "kismet.device.base.manuf": "Asus",
    "kismet.device.base.channel": 36,
    "kismet.device.base.frequency": 5180,
    "kismet.device.base.crypt": "WPA2",
    "kismet.device.base.first_time": 1700000000,
    "kismet.device.base.last_time": 1700000600,
    "kismet.device.base.signal": {"kismet.common.signal.last_signal_dbm": -55},
    "dot11.device": {
        "dot11.device.advertised_ssid_map": {
            "uuid-1": {"dot11.advertisedssid.ssid": "Lab-Net", "dot11.advertisedssid.cloaked": False},
        },
    },
}

CLIENT_DEVICE: dict[str, Any] = {
    "kismet.device.base.macaddr": "11:22:33:AA:BB:CC",
    "kismet.device.base.type": "Wi-Fi Device",
    "kismet.device.base.manuf": "Apple",
    "kismet.device.base.channel": 36,
    "kismet.device.base.signal": {"kismet.common.signal.last_signal_dbm": -71},
    "kismet.device.base.packets": {"kismet.common.packets.total": 4242},
    "dot11.device": {
        "dot11.device.probed_ssid_map": {
            "uuid-2": {"dot11.probedssid.ssid": "Home"},
            "uuid-3": {"dot11.probedssid.ssid": "Office"},
        },
        "dot11.device.last_bssid": "AA:BB:CC:00:11:22",
    },
}


# -------------------------------------------------------------------- client


def _client(handler: Any, token: str | None = "tok") -> KismetClient:
    return KismetClient(
        "http://kismet.test:2501",
        token=token,
        transport=httpx.MockTransport(handler),
    )


def test_client_requires_credentials() -> None:
    with pytest.raises(KismetError):
        KismetClient("http://kismet.test")


def test_client_sends_kismet_cookie() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/system/status.readonly.json"
        assert request.headers["cookie"] == "KISMET=tok"
        return httpx.Response(200, json={"kismet.system.version": "2025-09-R1"})

    with _client(handler) as client:
        assert client.system_status()["kismet.system.version"] == "2025-09-R1"


def test_client_basic_auth_variant() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["authorization"].startswith("Basic ")
        return httpx.Response(200, json={"kismet.system.timestamp": 1700000000})

    client = KismetClient(
        "http://kismet.test",
        username="admin",
        password="hunter2",
        transport=httpx.MockTransport(handler),
    )
    assert client.timestamp() == 1700000000


def test_devices_since_posts_fields() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/devices/last-time/1700000000/devices.json"
        assert request.method == "POST"
        payload = request.read()
        import json

        body = json.loads(payload)
        assert "fields" in body
        assert any("macaddr" in field for field in body["fields"])
        return httpx.Response(200, json={"kismet_device_list": [AP_DEVICE]})

    with _client(handler) as client:
        devices = client.devices_since(1700000000)
    assert devices == [AP_DEVICE]


def test_devices_all_vector_shape() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/devices/summary/devices.json"
        return httpx.Response(200, json=[CLIENT_DEVICE])

    with _client(handler) as client:
        devices = client.devices_all()
    assert devices == [CLIENT_DEVICE]


def test_client_http_error() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, text="denied")

    with _client(handler) as client, pytest.raises(KismetError, match="HTTP 401"):
        client.system_status()


# ------------------------------------------------------------------- mapping


def test_field_path_union_syntax() -> None:
    assert field_path(AP_DEVICE, "kismet.device.base.signal/kismet.common.signal.last_signal_dbm") == -55
    assert field_path(AP_DEVICE, "kismet.device.base.macaddr") == "AA:BB:CC:00:11:22"
    assert field_path(AP_DEVICE, "kismet.device.base.missing") is None


def test_advertised_ssids_value_map_and_vector() -> None:
    assert advertised_ssids(AP_DEVICE) == ["Lab-Net"]
    vector = {
        "dot11.device": {
            "dot11.device.advertised_ssid_map": [
                {"dot11.advertisedssid.ssid": "One"},
                {"dot11.advertisedssid.ssid": "Two"},
            ]
        }
    }
    assert advertised_ssids(vector) == ["One", "Two"]


def test_probe_ssids() -> None:
    assert sorted(probe_ssids(CLIENT_DEVICE)) == ["Home", "Office"]


def test_station_type_classification() -> None:
    assert station_type_from_device(AP_DEVICE) == "ap"
    assert station_type_from_device(CLIENT_DEVICE) == "station"
    bridge_ap = dict(AP_DEVICE, **{"kismet.device.base.type": "Wi-Fi Bridged AP"})
    assert station_type_from_device(bridge_ap) == "bridge-ap"
    bridge = dict(CLIENT_DEVICE, **{"kismet.device.base.type": "Wi-Fi Bridge"})
    assert station_type_from_device(bridge) == "bridge"


def test_network_documents_from_ap(boundary: SchemaBoundary) -> None:
    documents = network_documents(
        AP_DEVICE,
        base_url="http://kismet.test:2501",
        source_device_id="kismet:kismet.test:2501",
        dataset="kismet-test",
        now="2026-09-19T00:00:00+00:00",
    )
    assert len(documents) == 1
    document = documents[0]
    data = document["data"]
    assert data["bssid"] == "aa:bb:cc:00:11:22"
    assert data["ssid"] == "Lab-Net"
    assert data["security"] == "wpa2-psk"
    assert data["channel"] == 36
    assert data["frequency_mhz"] == 5180
    assert data["band"] == "5ghz"
    assert data["signal_dbm"] == -55
    assert data["vendor"] == "Asus"
    assert data["first_seen"] == "2023-11-14T22:13:20Z"
    assert data["source_network_id"] == "kismet:kismet.test:2501:aa:bb:cc:00:11:22"
    source = document["sources"][0]
    assert source["kind"] == "sensor"
    assert source["url"].endswith("/devices/summary/devices.json")
    boundary.validate(document)


def test_network_documents_cloaked_ap_without_ssid(boundary: SchemaBoundary) -> None:
    cloaked = {
        "kismet.device.base.macaddr": "00:00:00:00:00:01",
        "kismet.device.base.type": "Wi-Fi AP",
        "dot11.device": {"dot11.device.advertised_ssid_map": {}},
    }
    documents = network_documents(
        cloaked, base_url="http://k", source_device_id="kismet:k", now="2026-09-19T00:00:00+00:00"
    )
    assert len(documents) == 1
    assert documents[0]["data"]["ssid"] == ""
    boundary.validate(documents[0])


def test_network_documents_skips_clients() -> None:
    assert (
        network_documents(
            CLIENT_DEVICE, base_url="http://k", source_device_id="kismet:k"
        )
        == []
    )


def test_station_document_from_client(boundary: SchemaBoundary) -> None:
    station = station_document(
        CLIENT_DEVICE,
        base_url="http://kismet.test:2501",
        source_device_id="kismet:kismet.test:2501",
        dataset="kismet-test",
        now="2026-09-19T00:00:00+00:00",
    )
    assert station is not None
    data = station["data"]
    assert data["mac"] == "11:22:33:aa:bb:cc"
    assert data["station_type"] == "station"
    assert sorted(data["probe_ssids"]) == ["Home", "Office"]
    assert data["last_bssid"] == "aa:bb:cc:00:11:22"
    assert data["signal_dbm"] == -71
    assert data["packets"] == 4242
    assert data["vendor"] == "Apple"
    boundary.validate(station)


def test_station_document_skips_macless() -> None:
    assert (
        station_document(
            {"kismet.device.base.type": "Wi-Fi AP"},
            base_url="http://k",
            source_device_id="kismet:k",
        )
        is None
    )


def test_observed_at_station_relations(boundary: SchemaBoundary) -> None:
    station = station_document(
        CLIENT_DEVICE,
        base_url="http://k",
        source_device_id="kismet:k",
        now="2026-09-19T00:00:00+00:00",
    )
    networks = network_documents(
        AP_DEVICE, base_url="http://k", source_device_id="kismet:k", now="2026-09-19T00:00:00+00:00"
    )
    assert station is not None
    relations = observed_at_station_relations(
        station, networks, now="2026-09-19T00:00:00+00:00"
    )
    assert len(relations) == 1
    relation = relations[0]
    assert relation["data"]["predicate"] == OBSERVED_AT_STATION
    assert relation["data"]["subject"] == station["_id"]
    assert relation["data"]["object"] == networks[0]["_id"]
    boundary.validate(relation)
