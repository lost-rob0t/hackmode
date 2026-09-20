"""Envelope + supplemental validator coverage through the SchemaBoundary."""

from __future__ import annotations

import copy
from typing import Any

import pytest

from hackmode_wireless.transport import (
    NetworkContractError,
    SchemaBoundary,
    relation_document,
    wireless_network_id,
    wireless_station_id,
)


def network_doc(**data: Any) -> dict[str, Any]:
    return {
        "_id": wireless_network_id(data.get("bssid", "00:11:22:33:44:55"), "net", "wigle:x"),
        "dataset": "test",
        "dtype": "wireless-network",
        "schema_version": "0.9.0",
        "version": 1,
        "date_added": "2026-09-19T00:00:00+00:00",
        "date_updated": "2026-09-19T00:00:00+00:00",
        "sources": [],
        "evidence": [],
        "data": {"bssid": "00:11:22:33:44:55", "security": "wpa2-psk", **data},
    }


def station_doc(**data: Any) -> dict[str, Any]:
    return {
        "_id": wireless_station_id(data.get("mac", "11:22:33:44:55:66"), "kismet:k"),
        "dataset": "test",
        "dtype": "wireless-station",
        "schema_version": "0.9.0",
        "version": 1,
        "date_added": "2026-09-19T00:00:00+00:00",
        "date_updated": "2026-09-19T00:00:00+00:00",
        "sources": [],
        "evidence": [],
        "data": {"mac": "11:22:33:44:55:66", **data},
    }


def test_valid_wireless_network_passes(boundary: SchemaBoundary) -> None:
    boundary.validate(
        network_doc(
            ssid="net",
            channel=6,
            frequency_mhz=2437,
            band="2.4ghz",
            signal_dbm=-60,
            latitude=1.5,
            longitude=-2.5,
            location_accuracy_m=25.0,
            observations=3,
            client_count=1,
            first_seen="2026-01-01T00:00:00Z",
            last_seen="2026-09-19T12:00:00Z",
            source_network_id="wigle:x",
            vendor="Acme",
            hosted_host_id="starintel:host:abc",
            qos=3,
            cipher_suite="CCMP",
            auth_mode="PSK",
        )
    )


def test_valid_wireless_station_passes(boundary: SchemaBoundary) -> None:
    boundary.validate(
        station_doc(
            station_type="station",
            vendor="Apple",
            probe_ssids=["a", "b"],
            last_bssid="00:11:22:33:44:55",
            signal_dbm=-70,
            observations=2,
            first_seen="2026-01-01T00:00:00Z",
            last_seen="2026-09-19T12:00:00Z",
            source_device_id="kismet:k",
            packets=10,
            data_bytes=2048,
        )
    )


@pytest.mark.parametrize(
    "field", ["bssid", "security"],
)
def test_wireless_network_required_fields(boundary: SchemaBoundary, field: str) -> None:
    document = network_doc()
    document["data"].pop(field)
    with pytest.raises(NetworkContractError, match=field):
        boundary.validate(document)


def test_wireless_station_requires_mac(boundary: SchemaBoundary) -> None:
    document = station_doc()
    document["data"].pop("mac")
    with pytest.raises(NetworkContractError, match="mac"):
        boundary.validate(document)


def test_security_enum_enforced(boundary: SchemaBoundary) -> None:
    with pytest.raises(NetworkContractError, match="security"):
        boundary.validate(network_doc(security="wpa4"))


def test_band_enum_enforced(boundary: SchemaBoundary) -> None:
    with pytest.raises(NetworkContractError, match="band"):
        boundary.validate(network_doc(band="60ghz"))


def test_station_type_enum_enforced(boundary: SchemaBoundary) -> None:
    with pytest.raises(NetworkContractError, match="station_type"):
        boundary.validate(station_doc(station_type="router"))


def test_additional_properties_rejected(boundary: SchemaBoundary) -> None:
    with pytest.raises(NetworkContractError, match="extra"):
        boundary.validate(network_doc(extra="field"))
    with pytest.raises(NetworkContractError, match="extra"):
        boundary.validate(station_doc(extra="field"))


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("channel", 3.5),
        ("signal_dbm", True),
        ("observations", "many"),
        ("latitude", "north"),
        ("first_seen", "yesterday"),
    ],
)
def test_wireless_network_type_checks(boundary: SchemaBoundary, field: str, value: Any) -> None:
    with pytest.raises(NetworkContractError, match=field):
        boundary.validate(network_doc(**{field: value}))


def test_station_type_checks(boundary: SchemaBoundary) -> None:
    with pytest.raises(NetworkContractError, match="probe_ssids"):
        boundary.validate(station_doc(probe_ssids="Home"))
    with pytest.raises(NetworkContractError, match="packets"):
        boundary.validate(station_doc(packets=True))


def test_envelope_missing_required_key(boundary: SchemaBoundary) -> None:
    document = network_doc()
    del document["dataset"]
    with pytest.raises(NetworkContractError):
        boundary.validate(document)


def test_envelope_wrong_schema_version(boundary: SchemaBoundary) -> None:
    document = network_doc()
    document["schema_version"] = "0.8.0"
    with pytest.raises(NetworkContractError):
        boundary.validate(document)


def test_envelope_unknown_top_level_key(boundary: SchemaBoundary) -> None:
    document = network_doc()
    document["bogus"] = 1
    with pytest.raises(NetworkContractError):
        boundary.validate(document)


def test_envelope_bad_datetime(boundary: SchemaBoundary) -> None:
    document = network_doc()
    document["date_added"] = "not-a-time"
    with pytest.raises(NetworkContractError, match="date_added"):
        boundary.validate(document)


def test_relation_document_validates(boundary: SchemaBoundary) -> None:
    document = relation_document(
        subject="starintel:wireless-station:abc",
        predicate="observed_at_station",
        obj="starintel:wireless-network:def",
        dataset="test",
        now="2026-09-19T00:00:00+00:00",
        sources=[{"kind": "sensor", "name": "Kismet", "url": "http://k"}],
    )
    boundary.validate(document)


def test_boundary_does_not_mutate_shared_schema() -> None:
    first = SchemaBoundary.default()
    second = SchemaBoundary.default()
    doc = network_doc()
    first.validate(doc)
    copy.deepcopy(first)
    second.validate(doc)
