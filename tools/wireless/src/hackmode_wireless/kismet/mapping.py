"""Kismet device summaries to StarIntel wireless documents.

Kismet field paths (Brave-verified 2026-09-19 against kismetwireless docs
and REST examples):

* ``kismet.device.base.macaddr`` / ``.name`` / ``.type`` / ``.manuf`` /
  ``.frequency`` / ``.channel`` / ``.first_time`` / ``.last_time`` /
  ``.crypt``
* ``kismet.device.base.signal/kismet.common.signal.last_signal_dbm``
* 802.11 advertised SSIDs: ``dot11.device.advertised_ssid_map`` entries with
  ``dot11.advertisedssid.ssid`` / ``.cloaked`` (value-map or vector shaped)
* 802.11 probe requests: ``dot11.device.probed_ssid_map`` entries with
  ``dot11.probedssid.ssid``

TODO-verify: legacy ``kismet.dot11.device.lastssid`` (accepted as a
fallback), ``dot11.device.last_bssid``, and the total-packets path.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import UTC, datetime
from typing import Any

from hackmode_wireless.transport import (
    WIRELESS_NETWORK_DTYPE,
    WIRELESS_STATION_DTYPE,
    Document,
    JsonObject,
    build_envelope,
    normalize_mac,
    now_iso,
    relation_document,
    wireless_network_id,
    wireless_station_id,
)

DEFAULT_DATASET = "kismet"
OBSERVED_AT_STATION = "observed_at_station"


def field_path(device: Mapping[str, Any], path: str) -> Any:
    """Resolve a Kismet ``a.b/c.d`` field path inside a device summary."""
    current: Any = device
    for segment in path.split("/"):
        for key in (segment, f"kismet.{segment}"):
            if isinstance(current, dict) and key in current:
                current = current[key]
                break
        else:
            return None
    return current


def dot11_tree(device: Mapping[str, Any]) -> dict[str, Any]:
    for key in ("dot11.device", "kismet.dot11.device"):
        tree = device.get(key)
        if isinstance(tree, dict):
            return tree
    return {}


def ssid_entries(tree: Mapping[str, Any], map_key: str) -> list[dict[str, Any]]:
    """Advertised/probed SSID maps arrive as value-maps or vectors."""
    raw = tree.get(map_key)
    if isinstance(raw, dict):
        return [entry for entry in raw.values() if isinstance(entry, dict)]
    if isinstance(raw, list):
        return [entry for entry in raw if isinstance(entry, dict)]
    return []


def advertised_ssids(device: Mapping[str, Any]) -> list[str]:
    entries = ssid_entries(dot11_tree(device), "dot11.device.advertised_ssid_map")
    ssids: list[str] = []
    for entry in entries:
        ssid = entry.get("dot11.advertisedssid.ssid")
        if isinstance(ssid, str) and ssid:
            ssids.append(ssid)
    if not ssids:
        legacy = dot11_tree(device).get("dot11.device.lastssid") or dot11_tree(device).get(
            "kismet.dot11.device.lastssid"
        )
        if isinstance(legacy, str) and legacy:
            ssids.append(legacy)
    return ssids


def probe_ssids(device: Mapping[str, Any]) -> list[str]:
    entries = ssid_entries(dot11_tree(device), "dot11.device.probed_ssid_map")
    ssids: list[str] = []
    for entry in entries:
        ssid = entry.get("dot11.probedssid.ssid")
        if isinstance(ssid, str) and ssid:
            ssids.append(ssid)
    return ssids


def _is_ap(device: Mapping[str, Any]) -> bool:
    type_ = str(field_path(device, "kismet.device.base.type") or "")
    return "ap" in type_.lower() or bool(advertised_ssids(device))


def station_type_from_device(device: Mapping[str, Any]) -> str:
    """Classify a Kismet device onto the wireless-station station_type enum."""
    type_ = str(field_path(device, "kismet.device.base.type") or "").lower()
    has_bridge = "bridge" in type_
    has_ap = "ap" in type_ or bool(advertised_ssids(device))
    if has_bridge and has_ap:
        return "bridge-ap"
    if has_bridge:
        return "bridge"
    if has_ap:
        return "ap"
    if type_:
        return "station"
    return "unknown"


def _signal_dbm(device: Mapping[str, Any]) -> int | None:
    value = field_path(device, "kismet.device.base.signal/kismet.common.signal.last_signal_dbm")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return int(value)
    return None


def _frequency_mhz(device: Mapping[str, Any]) -> int | None:
    value = field_path(device, "kismet.device.base.frequency")
    if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0:
        return int(value)
    return None


def _channel(device: Mapping[str, Any]) -> int | None:
    value = field_path(device, "kismet.device.base.channel")
    if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0:
        return int(value)
    return None


def _iso_epoch(value: Any) -> str | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0:
        return datetime.fromtimestamp(int(value), tz=UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    return None


def _crypt_to_security(crypt: Any) -> str:
    from hackmode_wireless.wigle.mapping import map_encryption

    return map_encryption(crypt)


def source_record(base_url: str, path: str, now: str) -> JsonObject:
    from urllib.parse import urlparse

    host = urlparse(base_url).netloc or base_url
    return {
        "kind": "sensor",
        "name": "Kismet",
        "url": f"{base_url.rstrip('/')}{path}",
        "access_method": "kismet-rest",
        "sensor": host,
        "retrieved_at": now,
    }


def network_documents(
    device: Mapping[str, Any],
    *,
    base_url: str,
    source_device_id: str,
    dataset: str = DEFAULT_DATASET,
    now: str | None = None,
) -> list[Document]:
    """Emit wireless-network documents for one Kismet device's advertised SSIDs.

    APs without any advertised SSID (fully cloaked) still emit one document
    with an empty ssid.
    """
    from hackmode_wireless.wigle.mapping import band_from_channel, band_from_frequency_mhz

    mac = normalize_mac(field_path(device, "kismet.device.base.macaddr"))
    if not mac:
        return []
    if not _is_ap(device):
        return []
    timestamp = now or now_iso()
    path = "/devices/summary/devices.json"
    sources = [source_record(base_url, path, timestamp)]
    ssids = advertised_ssids(device) or [""]
    crypt = field_path(device, "kismet.device.base.crypt")
    manuf = field_path(device, "kismet.device.base.manuf")
    channel = _channel(device)
    frequency = _frequency_mhz(device)
    band = band_from_frequency_mhz(frequency) if frequency else None
    if band is None and channel is not None:
        band = band_from_channel(channel)
    signal = _signal_dbm(device)
    first_seen = _iso_epoch(field_path(device, "kismet.device.base.first_time"))
    last_seen = _iso_epoch(field_path(device, "kismet.device.base.last_time"))
    source_network_id = f"{source_device_id}:{mac}"

    documents: list[Document] = []
    for ssid in ssids:
        data: JsonObject = {
            "bssid": mac,
            "ssid": ssid,
            "security": _crypt_to_security(crypt),
            "source_network_id": source_network_id,
        }
        if channel is not None:
            data["channel"] = channel
        if frequency is not None:
            data["frequency_mhz"] = frequency
        if band is not None:
            data["band"] = band
        if signal is not None:
            data["signal_dbm"] = signal
        if isinstance(manuf, str) and manuf:
            data["vendor"] = manuf
        if first_seen:
            data["first_seen"] = first_seen
        if last_seen:
            data["last_seen"] = last_seen
        documents.append(
            build_envelope(
                _id=wireless_network_id(mac, ssid, source_network_id),
                dtype=WIRELESS_NETWORK_DTYPE,
                dataset=dataset,
                data=data,
                sources=sources,
                now=timestamp,
            )
        )
    return documents


def station_document(
    device: Mapping[str, Any],
    *,
    base_url: str,
    source_device_id: str,
    dataset: str = DEFAULT_DATASET,
    now: str | None = None,
) -> Document | None:
    """Emit a wireless-station document for one Kismet device."""
    mac = normalize_mac(field_path(device, "kismet.device.base.macaddr"))
    if not mac:
        return None
    timestamp = now or now_iso()
    probes = probe_ssids(device)
    last_bssid = normalize_mac(dot11_tree(device).get("dot11.device.last_bssid"))
    signal = _signal_dbm(device)
    manuf = field_path(device, "kismet.device.base.manuf")
    packets = field_path(device, "kismet.device.base.packets/kismet.common.packets.total")
    first_seen = _iso_epoch(field_path(device, "kismet.device.base.first_time"))
    last_seen = _iso_epoch(field_path(device, "kismet.device.base.last_time"))
    data: JsonObject = {
        "mac": mac,
        "station_type": station_type_from_device(device),
        "source_device_id": source_device_id,
    }
    if probes:
        data["probe_ssids"] = probes
    if last_bssid:
        data["last_bssid"] = last_bssid
    if signal is not None:
        data["signal_dbm"] = signal
    if isinstance(manuf, str) and manuf:
        data["vendor"] = manuf
    if isinstance(packets, (int, float)) and not isinstance(packets, bool):
        data["packets"] = int(packets)
    if first_seen:
        data["first_seen"] = first_seen
    if last_seen:
        data["last_seen"] = last_seen
    return build_envelope(
        _id=wireless_station_id(mac, source_device_id),
        dtype=WIRELESS_STATION_DTYPE,
        dataset=dataset,
        data=data,
        sources=[source_record(base_url, "/devices/summary/devices.json", timestamp)],
        now=timestamp,
    )


def observed_at_station_relations(
    station: Document,
    networks: list[Document],
    *,
    dataset: str = DEFAULT_DATASET,
    now: str | None = None,
) -> list[Document]:
    """Relation documents linking a station to each network it was observed at."""
    timestamp = now or now_iso()
    return [
        relation_document(
            subject=station["_id"],
            predicate=OBSERVED_AT_STATION,
            obj=network["_id"],
            dataset=dataset,
            now=timestamp,
            sources=list(station["sources"]),
            note="station observed at access point by Kismet",
        )
        for network in networks
    ]
