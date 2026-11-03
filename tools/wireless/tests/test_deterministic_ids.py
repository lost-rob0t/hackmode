"""Deterministic identity across reruns and normalization behaviour."""

from __future__ import annotations

from hackmode_wireless.kismet.mapping import network_documents, station_document
from hackmode_wireless.transport import deterministic_id, wireless_network_id, wireless_station_id
from hackmode_wireless.wigle.mapping import network_document as wigle_network_document

WIGLE_RESULT = {
    "netid": "0A:2C:EF:3D:25:1B",
    "ssid": "CaSe   Test",
    "trilat": 1.0,
    "trilong": 2.0,
    "encryption": "WPA2",
    "channel": 36,
}


def test_wigle_ids_stable_across_reruns() -> None:
    first = wigle_network_document(dict(WIGLE_RESULT), now="2026-09-19T00:00:00+00:00")
    second = wigle_network_document(dict(WIGLE_RESULT), now="2026-12-31T23:59:59+00:00")
    assert first["_id"] == second["_id"]
    assert first["_id"].startswith("starintel:wireless-network:")
    # timestamp changes must not leak into identity
    assert first["date_added"] != second["date_added"]


def test_wigle_ssid_normalization_in_identity() -> None:
    base = wigle_network_document(dict(WIGLE_RESULT), now="2026-09-19T00:00:00+00:00")
    variant = wigle_network_document(
        {**WIGLE_RESULT, "ssid": "case  test"}, now="2026-09-19T00:00:00+00:00"
    )
    assert base["_id"] == variant["_id"]


def test_wigle_bssid_case_and_format_normalized() -> None:
    base = wigle_network_document(dict(WIGLE_RESULT), now="2026-09-19T00:00:00+00:00")
    variant = wigle_network_document(
        {**WIGLE_RESULT, "netid": "0a2cef3d251b"}, now="2026-09-19T00:00:00+00:00"
    )
    assert base["_id"] == variant["_id"]
    assert variant["data"]["bssid"] == "0a:2c:ef:3d:25:1b"


def test_wigle_bssid_partitions_identity() -> None:
    base = wigle_network_document(dict(WIGLE_RESULT), now="2026-09-19T00:00:00+00:00")
    other = wigle_network_document(
        {**WIGLE_RESULT, "netid": "0A:2C:EF:3D:25:1C"}, now="2026-09-19T00:00:00+00:00"
    )
    assert base["_id"] != other["_id"]


def test_kismet_ids_stable_across_polls() -> None:
    device = {
        "kismet.device.base.macaddr": "AA:BB:CC:00:11:22",
        "kismet.device.base.type": "Wi-Fi AP",
        "dot11.device": {
            "dot11.device.advertised_ssid_map": {"u": {"dot11.advertisedssid.ssid": "Net"}},
        },
    }
    first = network_documents(device, base_url="http://k", source_device_id="kismet:k", now="2026-09-19T00:00:00+00:00")
    second = network_documents(device, base_url="http://k", source_device_id="kismet:k", now="2027-01-01T00:00:00+00:00")
    assert [doc["_id"] for doc in first] == [doc["_id"] for doc in second]

    station_one = station_document(device, base_url="http://k", source_device_id="kismet:k", now="2026-09-19T00:00:00+00:00")
    station_two = station_document(device, base_url="http://k", source_device_id="kismet:k", now="2027-01-01T00:00:00+00:00")
    assert station_one is not None and station_two is not None
    assert station_one["_id"] == station_two["_id"]


def test_kismet_source_device_id_partitions_identity() -> None:
    device = {
        "kismet.device.base.macaddr": "AA:BB:CC:00:11:22",
        "kismet.device.base.type": "Wi-Fi AP",
    }
    one = network_documents(device, base_url="http://k1", source_device_id="kismet:k1")
    two = network_documents(device, base_url="http://k2", source_device_id="kismet:k2")
    assert one[0]["_id"] != two[0]["_id"]


def test_deterministic_id_shape() -> None:
    value = deterministic_id("wireless-network", ("a", "b", "c"))
    assert value.startswith("starintel:wireless-network:")
    assert len(value.rsplit(":", 1)[1]) == 64
    assert wireless_network_id("A", "s", "n") != wireless_network_id("B", "s", "n")
    assert wireless_station_id("A", "n") != wireless_station_id("A", "m")
