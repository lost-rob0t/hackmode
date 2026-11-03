"""WiGLE search results to StarIntel wireless-network documents.

Security mapping table (WiGLE ``encryption`` + ``wep`` flag → StarIntel
``security`` enum).  WiGLE's v2 filter vocabulary is
``None``/``WEP``/``WPA``/``WPA2``/``WPA3``/``Unknown`` (case-insensitive);
result records carry the same vocabulary plus a legacy ``wep`` flag.  The
API does not distinguish PSK from enterprise modes, so plain WPA/WPA2/WPA3
map to the ``-psk`` variants (most common in the wild); explicit
``WPA2-Enterprise``/``WPA3-Enterprise`` strings are honoured if a future API
revision emits them.  Transition networks advertising both WPA2 and WPA3
(e.g. ``WPA2/WPA3`` or ``WPA2+WPA3``) map to ``wpa2wpa3-psk``.

| WiGLE encryption            | wep flag | StarIntel security   |
| --------------------------- | -------- | -------------------- |
| "None"/""/absent            | any      | open                 |
| WEP (or wep flag truthy)    |          | wep                  |
| WPA                         |          | wpa-psk              |
| WPA2                        |          | wpa2-psk             |
| WPA3                        |          | wpa3-psk             |
| WPA2 + WPA3 (compound)      |          | wpa2wpa3-psk         |
| WPA2-Enterprise             |          | wpa2-enterprise      |
| WPA3-Enterprise             |          | wpa3-enterprise      |
| "Unknown"/anything else     |          | unknown              |

TODO-verify: WiGLE search results do not expose per-observation
``fnoise``/``signal`` ranges (those live on the detail endpoint); the search
mapping therefore emits no ``signal_dbm``.
"""

from __future__ import annotations

import re
from datetime import UTC, datetime
from typing import Any

from hackmode_wireless.transport import (
    WIRELESS_NETWORK_DTYPE,
    Document,
    JsonObject,
    build_envelope,
    deterministic_id,
    normalize_mac,
    now_iso,
    wireless_network_id,
)

WIGLE_SOURCE_NAME = "WiGLE"
WIGLE_SEARCH_URL = "https://api.wigle.net/api/v2/network/search"
DEFAULT_DATASET = "wigle"

_TOKEN_SPLIT_RE = re.compile(r"[/,;+\s]+")
_TRUTHY = {"t", "true", "y", "yes", "1", "?"}

_SIMPLE_ENCRYPTION_MAP = {
    "none": "open",
    "wep": "wep",
    "wpa": "wpa-psk",
    "wpa2": "wpa2-psk",
    "wpa3": "wpa3-psk",
    "wpa2-enterprise": "wpa2-enterprise",
    "wpa3-enterprise": "wpa3-enterprise",
    "wpa2enterprise": "wpa2-enterprise",
    "wpa3enterprise": "wpa3-enterprise",
    "unknown": "unknown",
}


def _wep_flag_truthy(wep: Any) -> bool:
    if isinstance(wep, bool):
        return wep
    if isinstance(wep, (int, float)):
        return wep != 0
    return isinstance(wep, str) and wep.strip().lower() in _TRUTHY


def map_encryption(encryption: Any, wep: Any = None) -> str:
    """Map the WiGLE encryption vocabulary onto the StarIntel security enum."""
    tokens = [
        token.strip().lower()
        for token in _TOKEN_SPLIT_RE.split(str(encryption or ""))
        if token.strip()
    ]
    if not tokens:
        tokens = ["none"]
    if _wep_flag_truthy(wep) and not any(token.startswith("wep") for token in tokens):
        tokens.append("wep")

    mapped = [_SIMPLE_ENCRYPTION_MAP.get(token, "unknown") for token in tokens]
    if "unknown" in mapped and len(mapped) > 1:
        mapped = [value for value in mapped if value != "unknown"] or ["unknown"]
    if "open" in mapped and len(mapped) > 1:
        mapped = [value for value in mapped if value != "open"] or ["open"]
    has_wpa = any(value.startswith("wpa") for value in mapped)
    if "wep" in mapped and has_wpa:
        mapped = [value for value in mapped if value != "wep"] or ["wep"]

    has_wpa2 = "wpa2-psk" in mapped or "wpa2-enterprise" in mapped
    has_wpa3 = "wpa3-psk" in mapped or "wpa3-enterprise" in mapped
    if has_wpa2 and has_wpa3:
        return "wpa2wpa3-psk"
    for preferred in (
        "wpa3-enterprise",
        "wpa3-psk",
        "wpa2-enterprise",
        "wpa2-psk",
        "wpa-psk",
        "wep",
        "open",
    ):
        if preferred in mapped:
            return preferred
    return mapped[0] if mapped else "unknown"


def band_from_channel(channel: int | None) -> str:
    """Derive the band enum from a Wi-Fi channel number.

    2.4 GHz occupies channels 1-14 and 5 GHz 15-196 in the classic numbering
    WiGLE reports.  TODO-verify: 6 GHz re-uses low channel numbers in the new
    numbering, so unmapped channels fall back to ``unknown`` unless a
    frequency is available (``band_from_frequency_mhz``).
    """
    if channel is None or channel <= 0:
        return "unknown"
    if 1 <= channel <= 14:
        return "2.4ghz"
    if 15 <= channel <= 196:
        return "5ghz"
    return "unknown"


def band_from_frequency_mhz(frequency_mhz: int | None) -> str:
    if frequency_mhz is None or frequency_mhz <= 0:
        return "unknown"
    if frequency_mhz < 3000:
        return "2.4ghz"
    if 4900 <= frequency_mhz < 5925:
        return "5ghz"
    if 5925 <= frequency_mhz <= 7125:
        return "6ghz"
    return "unknown"


def _wigle_time(value: Any) -> str | None:
    """Normalize WiGLE timestamps ("2014-07-02T14:00:00.000Z") to ISO-8601 Z."""
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip().replace(" ", "T", 1)
    if text.endswith(("Z", "z")):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _int_or_none(value: Any) -> int | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str) and value.strip().isdigit():
        return int(value.strip())
    return None


def _float_or_none(value: Any) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip())
        except ValueError:
            return None
    return None


def wigle_source_record(query: str, now: str) -> JsonObject:
    """Source record citing the exact API call."""
    return {
        "kind": "api",
        "name": WIGLE_SOURCE_NAME,
        "url": WIGLE_SEARCH_URL,
        "query": query,
        "access_method": "wigle-api-v2-basic-auth",
        "retrieved_at": now,
    }


def network_document(
    result: dict[str, Any],
    *,
    dataset: str = DEFAULT_DATASET,
    now: str | None = None,
    query: str = "",
) -> Document:
    """Map one WiGLE network/search result to a wireless-network document."""
    netid = result.get("netid")
    bssid = normalize_mac(netid)
    if not netid or not bssid:
        raise ValueError("WiGLE result is missing netid")
    source_network_id = f"wigle:{bssid}"
    ssid = result.get("ssid") if isinstance(result.get("ssid"), str) else ""
    channel = _int_or_none(result.get("channel"))
    qos = _int_or_none(result.get("qos"))
    timestamp = now or now_iso()
    data: JsonObject = {
        "bssid": bssid,
        "ssid": ssid,
        "security": map_encryption(result.get("encryption"), result.get("wep")),
        "source_network_id": source_network_id,
    }
    if channel is not None and channel > 0:
        data["channel"] = channel
        data["band"] = band_from_channel(channel)
    if qos is not None:
        data["qos"] = qos
    trilat = _float_or_none(result.get("trilat"))
    trilong = _float_or_none(result.get("trilong"))
    if trilat is not None:
        data["latitude"] = trilat
    if trilong is not None:
        data["longitude"] = trilong
    first_seen = _wigle_time(result.get("firsttime"))
    last_seen = _wigle_time(result.get("lasttime"))
    if first_seen:
        data["first_seen"] = first_seen
    if last_seen:
        data["last_seen"] = last_seen

    return build_envelope(
        _id=wireless_network_id(bssid, ssid, source_network_id),
        dtype=WIRELESS_NETWORK_DTYPE,
        dataset=dataset,
        data=data,
        sources=[wigle_source_record(query, timestamp)],
        now=timestamp,
    )


def host_document(
    network: Document,
    *,
    dataset: str = DEFAULT_DATASET,
    now: str | None = None,
) -> Document:
    """Optional host emission for a WiGLE BSSID (v0.9 base ``host`` dtype).

    Also links the network back through ``data.hosted_host_id``.
    """
    timestamp = now or now_iso()
    data = network["data"]
    host_data: JsonObject = {
        "mac": data["bssid"],
        "device_type": "wifi-access-point",
    }
    if data.get("source_network_id"):
        host_data["network_id"] = data["source_network_id"]
    if data.get("first_seen"):
        host_data["first_seen"] = data["first_seen"]
    if data.get("last_seen"):
        host_data["last_seen"] = data["last_seen"]
    host_id = deterministic_id("host", (data["bssid"],))
    data["hosted_host_id"] = host_id
    document = build_envelope(
        _id=host_id,
        dtype="host",
        dataset=dataset,
        data=host_data,
        sources=list(network["sources"]),
        now=timestamp,
    )
    document["related_ids"] = [network["_id"]]
    return document
