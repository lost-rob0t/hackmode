"""Kismet REST API client.

Verified against Kismet's documented REST surface (2026-09-19, Brave-checked
against kismetwireless docs and python-kismet-rest):

* Auth: API token consumers supply the token via the ``KISMET`` cookie (or
  URI parameter); user/password via HTTP Basic.  Env: ``KISMET_TOKEN`` or
  ``KISMET_USER``/``KISMET_PASSWORD``.
* ``GET /system/status.readonly.json`` — unauthenticated status probe.
* ``GET /system/timestamp.json`` — server timestamp used as the poll cursor.
* ``POST /devices/summary/devices.json`` with ``{"fields": [...]}`` — full
  device summary with field simplification; field paths may use the
  ``a.b/c.d`` union syntax (e.g.
  ``kismet.device.base.signal/kismet.common.signal.last_signal_dbm``).
* ``POST /devices/last-time/{TS}/devices.json`` — devices new or modified
  since server timestamp TS (plus a mutation flag and report timestamp).

TODO-verify: the exact JSON keys of the last-time response envelope; the
client accepts both a bare vector and ``{"kismet_device_list": [...]}``
shapes and refreshes the cursor via ``/system/timestamp.json``.
TODO-verify: ``kismet.device.base.packets.total`` and
``dot11.device.last_bssid`` field paths (requested defensively).
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

LOGGER = logging.getLogger(__name__)

DEFAULT_BASE_URL = "http://127.0.0.1:2501"
USER_AGENT = "hackmode-wireless/0.1 (kismet collector)"

KISMET_DEVICE_FIELDS: tuple[str, ...] = (
    "kismet.device.base.key",
    "kismet.device.base.macaddr",
    "kismet.device.base.name",
    "kismet.device.base.type",
    "kismet.device.base.manuf",
    "kismet.device.base.frequency",
    "kismet.device.base.channel",
    "kismet.device.base.first_time",
    "kismet.device.base.last_time",
    "kismet.device.base.crypt",
    "kismet.device.base.packets/kismet.common.packets.total",  # TODO-verify packets path
    "kismet.device.base.signal/kismet.common.signal.last_signal_dbm",
    "dot11.device/dot11.device.advertised_ssid_map/dot11.advertisedssid.ssid",
    "dot11.device/dot11.device.advertised_ssid_map/dot11.advertisedssid.cloaked",
    "dot11.device/dot11.device.probed_ssid_map/dot11.probedssid.ssid",
    "dot11.device/dot11.device.last_bssid",  # TODO-verify field name
)


class KismetError(RuntimeError):
    """Kismet REST API error."""


class KismetClient:
    """Thin Kismet REST client; transport injectable for hermetic tests."""

    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        *,
        token: str | None = None,
        username: str | None = None,
        password: str | None = None,
        transport: httpx.BaseTransport | None = None,
        timeout: float = 30.0,
    ) -> None:
        if not (token or (username and password)):
            raise KismetError("Kismet auth requires KISMET_TOKEN or KISMET_USER/KISMET_PASSWORD")
        self.base_url = base_url.rstrip("/")
        cookies: dict[str, str] = {"KISMET": token} if token else {}
        auth = (username, password) if username and password else None
        self._client = httpx.Client(
            base_url=self.base_url,
            auth=auth,
            cookies=cookies,
            headers={"User-Agent": USER_AGENT},
            timeout=timeout,
            transport=transport,
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> KismetClient:
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def _get(self, path: str) -> Any:
        response = self._client.get(path)
        if response.status_code >= 400:
            raise KismetError(
                f"Kismet {path} returned HTTP {response.status_code}: {response.text[:200]}"
            )
        return response.json()

    def _post(self, path: str, payload: dict[str, Any]) -> Any:
        response = self._client.post(path, json=payload)
        if response.status_code >= 400:
            raise KismetError(
                f"Kismet {path} returned HTTP {response.status_code}: {response.text[:200]}"
            )
        return response.json()

    def system_status(self) -> dict[str, Any]:
        payload = self._get("/system/status.readonly.json")
        if not isinstance(payload, dict):
            raise KismetError("Kismet status returned a non-object payload")
        return payload

    def timestamp(self) -> int:
        payload = self._get("/system/timestamp.json")
        value = payload.get("kismet.system.timestamp") if isinstance(payload, dict) else payload
        if isinstance(value, (int, float)):
            return int(value)
        raise KismetError(f"Kismet timestamp returned unexpected payload: {payload!r}")

    def _devices(self, path: str, fields: tuple[str, ...]) -> list[dict[str, Any]]:
        payload = self._post(path, {"fields": list(fields)})
        devices: Any
        if isinstance(payload, list):
            devices = payload
        elif isinstance(payload, dict):
            devices = payload.get("kismet_device_list", [])
        else:
            raise KismetError(f"Kismet {path} returned unexpected payload shape")
        if not isinstance(devices, list):
            raise KismetError(f"Kismet {path} returned non-list devices")
        return [device for device in devices if isinstance(device, dict)]

    def devices_all(self, fields: tuple[str, ...] = KISMET_DEVICE_FIELDS) -> list[dict[str, Any]]:
        """Full device summary (POST /devices/summary/devices.json)."""
        return self._devices("/devices/summary/devices.json", fields)

    def devices_since(
        self,
        ts: int,
        fields: tuple[str, ...] = KISMET_DEVICE_FIELDS,
    ) -> list[dict[str, Any]]:
        """Devices new or modified since server timestamp ``ts``."""
        return self._devices(f"/devices/last-time/{int(ts)}/devices.json", fields)


def client_from_env() -> KismetClient:
    """Build a client from STARINTEL_KISMET_URL + KISMET_* credentials."""
    import os

    base_url = os.environ.get("STARINTEL_KISMET_URL", DEFAULT_BASE_URL)
    token = os.environ.get("KISMET_TOKEN") or None
    username = os.environ.get("KISMET_USER") or None
    password = os.environ.get("KISMET_PASSWORD") or None
    return KismetClient(
        base_url,
        token=token,
        username=username,
        password=password,
    )
