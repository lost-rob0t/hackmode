"""WiGLE mapping coverage: every security-enum branch, geo/band fields, hosts."""

from __future__ import annotations

import pytest

from hackmode_wireless.transport import (
    SchemaBoundary,
    normalize_ssid,
)
from hackmode_wireless.wigle.mapping import (
    band_from_channel,
    band_from_frequency_mhz,
    host_document,
    map_encryption,
    network_document,
)

WIGLE_RESULT = {
    "netid": "00:00:00:00:04:26",
    "ssid": "McDonalds Free WiFi",
    "trilat": 29.92946053,
    "trilong": -95.95930481,
    "qos": 5,
    "transid": "20140703-00000",
    "firsttime": "2014-07-02T14:00:00.000Z",
    "lasttime": "2015-09-14T16:00:00.000Z",
    "lastupdt": "2015-09-14T16:00:00.000Z",
    "type": "????",
    "comment": None,
    "wep": "?",
    "bcninterval": 0,
    "freenet": "?",
    "dhcp": "?",
    "paynet": "?",
    "userfound": False,
    "channel": 6,
    "encryption": "unknown",
    "country": "US",
    "region": "TX",
    "city": "Waller",
}


@pytest.mark.parametrize(
    ("encryption", "wep", "expected"),
    [
        ("None", None, "open"),
        ("", None, "open"),
        (None, None, "open"),
        ("WEP", None, "wep"),
        ("None", "T", "wep"),
        ("unknown", "true", "wep"),
        ("WPA", None, "wpa-psk"),
        ("WPA2", None, "wpa2-psk"),
        ("WPA3", None, "wpa3-psk"),
        ("WPA2/WPA3", None, "wpa2wpa3-psk"),
        ("WPA2+WPA3", None, "wpa2wpa3-psk"),
        ("WPA2,WPA3", None, "wpa2wpa3-psk"),
        ("WPA2-Enterprise", None, "wpa2-enterprise"),
        ("WPA3-Enterprise", None, "wpa3-enterprise"),
        ("Unknown", None, "unknown"),
        ("MagicCrypto", None, "unknown"),
        ("wpa2", None, "wpa2-psk"),
    ],
)
def test_every_security_enum_branch(encryption: str | None, wep: object, expected: str) -> None:
    assert map_encryption(encryption, wep) == expected


def test_band_from_channel() -> None:
    assert band_from_channel(1) == "2.4ghz"
    assert band_from_channel(14) == "2.4ghz"
    assert band_from_channel(36) == "5ghz"
    assert band_from_channel(165) == "5ghz"
    assert band_from_channel(0) == "unknown"
    assert band_from_channel(None) == "unknown"
    assert band_from_channel(300) == "unknown"  # 6ghz numbering unverified


def test_band_from_frequency() -> None:
    assert band_from_frequency_mhz(2412) == "2.4ghz"
    assert band_from_frequency_mhz(2484) == "2.4ghz"
    assert band_from_frequency_mhz(5180) == "5ghz"
    assert band_from_frequency_mhz(5825) == "5ghz"
    assert band_from_frequency_mhz(5955) == "6ghz"
    assert band_from_frequency_mhz(6985) == "6ghz"
    assert band_from_frequency_mhz(None) == "unknown"


def test_network_document_maps_fields(boundary: SchemaBoundary) -> None:
    document = network_document(
        {**WIGLE_RESULT, "encryption": "WPA2", "wep": "?"},
        dataset="wigle-test",
        now="2026-09-19T00:00:00+00:00",
        query="latrange1=29.9",
    )
    data = document["data"]
    assert document["dtype"] == "wireless-network"
    assert data["bssid"] == "00:00:00:00:04:26"
    assert data["ssid"] == "McDonalds Free WiFi"
    assert data["security"] == "wpa2-psk"
    assert data["channel"] == 6
    assert data["band"] == "2.4ghz"
    assert data["qos"] == 5
    assert data["latitude"] == pytest.approx(29.92946053)
    assert data["longitude"] == pytest.approx(-95.95930481)
    assert data["first_seen"] == "2014-07-02T14:00:00Z"
    assert data["last_seen"] == "2015-09-14T16:00:00Z"
    assert data["source_network_id"] == "wigle:00:00:00:00:04:26"
    assert "signal_dbm" not in data  # search results carry no signal_dbm
    source = document["sources"][0]
    assert source["name"] == "WiGLE"
    assert source["url"].endswith("/api/v2/network/search")
    assert source["query"] == "latrange1=29.9"
    assert source["access_method"] == "wigle-api-v2-basic-auth"
    boundary.validate(document)


def test_network_document_requires_netid() -> None:
    with pytest.raises(ValueError, match="netid"):
        network_document({"ssid": "x"})


def test_network_document_open_ssidless(boundary: SchemaBoundary) -> None:
    document = network_document(
        {"netid": "AA:BB:CC:DD:EE:FF", "encryption": "None", "channel": 0},
        now="2026-09-19T00:00:00+00:00",
    )
    assert document["data"]["security"] == "open"
    assert document["data"]["ssid"] == ""
    assert "channel" not in document["data"]
    assert "band" not in document["data"]
    boundary.validate(document)


def test_host_document_links_network(boundary: SchemaBoundary) -> None:
    document = network_document(
        {**WIGLE_RESULT, "encryption": "WEP", "wep": "T"},
        now="2026-09-19T00:00:00+00:00",
    )
    host = host_document(document, now="2026-09-19T00:00:00+00:00")
    assert host["dtype"] == "host"
    assert host["data"]["mac"] == "00:00:00:00:04:26"
    assert host["data"]["device_type"] == "wifi-access-point"
    assert host["data"]["network_id"] == "wigle:00:00:00:00:04:26"
    assert document["data"]["hosted_host_id"] == host["_id"]
    assert host["related_ids"] == [document["_id"]]
    boundary.validate(host)
    boundary.validate(document)  # hosted_host_id is an allowed network field


def test_ssid_normalization() -> None:
    assert normalize_ssid("  Foo   Bar ") == "foo bar"
    assert normalize_ssid(None) == ""
    assert normalize_ssid("ABC") == normalize_ssid("abc")
