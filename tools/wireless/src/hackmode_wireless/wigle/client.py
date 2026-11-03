"""WiGLE API v2 client (https://api.wigle.net).

Verified against the WiGLE v2 API surface (2026-09-19, Brave-checked):

* Auth: HTTP Basic with the account's API name as user and API token as
  password (api.wigle.net account keys).
* ``GET /api/v2/network/search`` with ``latrange1``/``latrange2``/
  ``longrange1``/``longrange2`` (bbox), ``ssid``, ``netid`` (>= 3 octets),
  ``onlymine``, ``resultsPerPage`` (site auth bounded at 100), and
  ``searchafter`` pagination (pass back the previous page's ``searchAfter``).
  Result records carry ``netid``, ``ssid``, ``trilat``, ``trilong``, ``qos``,
  ``channel``, ``encryption`` ("None"/"WEP"/"WPA"/"WPA2"/"WPA3"/"Unknown"),
  ``wep`` flag, ``firsttime``/``lasttime``/``lastupdt``, ``nettype``/``type``,
  ``transid``, ``freenet``, ``paynet``, ``dhcp``, ``bcninterval``,
  ``userfound``, and address fields.
  Responses: ``success``, ``totalResults``, ``resultCount``, ``results``,
  ``searchAfter`` (string), ``search_after`` (deprecated int).
  WiGLE daily query counts are throttled per account; the client keeps a
  configurable inter-page delay for politeness.
* ``GET /api/v2/network/{netid}`` network detail (per operator contract);
  the swagger also documents a query-parameter detail form, so the client
  falls back to ``/api/v2/network/detail?netid=...`` on 404.
* ``GET /api/v2/bluetooth/search`` Bluetooth/BLE search with the same bbox
  ranges plus ``name``/``namelike``/``showble``/``showbt``.

TODO-verify: search-result ``fnoise``/``signal`` ranges (observation-level
fields on the detail endpoint) are not mapped by the search path.
TODO-verify: the legacy ``lastnetid`` pagination parameter is used only as a
fallback when a response carries no ``searchAfter``.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from typing import Any

import httpx

LOGGER = logging.getLogger(__name__)

BASE_URL = "https://api.wigle.net"
SEARCH_PATH = "/api/v2/network/search"
BLUETOOTH_SEARCH_PATH = "/api/v2/bluetooth/search"
MAX_RESULTS_PER_PAGE = 100
USER_AGENT = "hackmode-wireless/0.1 (wigle collector; https://github.com/lost-rob0t/hackmode)"


class WigleError(RuntimeError):
    """WiGLE API error."""


@dataclass(frozen=True, slots=True)
class WigleSearch:
    """Search parameters for /api/v2/network/search (bbox and/or ssid/netid)."""

    latrange1: float | None = None
    latrange2: float | None = None
    longrange1: float | None = None
    longrange2: float | None = None
    ssid: str | None = None
    netid: str | None = None
    onlymine: bool = False
    max_pages: int = 10
    results_per_page: int = MAX_RESULTS_PER_PAGE
    page_delay: float = 1.0

    def initial_params(self) -> dict[str, Any]:
        params: dict[str, Any] = {
            "resultsPerPage": min(self.results_per_page, MAX_RESULTS_PER_PAGE)
        }
        for name in ("latrange1", "latrange2", "longrange1", "longrange2"):
            value = getattr(self, name)
            if value is not None:
                params[name] = value
        if self.ssid:
            params["ssid"] = self.ssid
        if self.netid:
            params["netid"] = self.netid
        if self.onlymine:
            params["onlymine"] = "true"
        return params


@dataclass(frozen=True, slots=True)
class WigleBluetoothSearch:
    latrange1: float | None = None
    latrange2: float | None = None
    longrange1: float | None = None
    longrange2: float | None = None
    name: str | None = None
    namelike: str | None = None
    netid: str | None = None
    showble: bool = True
    showbt: bool = True
    max_pages: int = 10
    results_per_page: int = MAX_RESULTS_PER_PAGE
    page_delay: float = 1.0

    def initial_params(self) -> dict[str, Any]:
        params: dict[str, Any] = {
            "resultsPerPage": min(self.results_per_page, MAX_RESULTS_PER_PAGE),
            "showble": "true" if self.showble else "false",
            "showbt": "true" if self.showbt else "false",
        }
        for name in ("latrange1", "latrange2", "longrange1", "longrange2"):
            value = getattr(self, name)
            if value is not None:
                params[name] = value
        if self.name:
            params["name"] = self.name
        if self.namelike:
            params["namelike"] = self.namelike
        if self.netid:
            params["netid"] = self.netid
        return params


class WigleClient:
    """Thin WiGLE v2 HTTP client; transport injectable for hermetic tests."""

    def __init__(
        self,
        api_name: str,
        api_token: str,
        *,
        base_url: str = BASE_URL,
        transport: httpx.BaseTransport | None = None,
        timeout: float = 30.0,
        page_delay: float = 1.0,
    ) -> None:
        if not api_name or not api_token:
            raise WigleError("WiGLE API name and token are required")
        self.base_url = base_url.rstrip("/")
        self.page_delay = page_delay
        self._client = httpx.Client(
            base_url=self.base_url,
            auth=(api_name, api_token),
            headers={"User-Agent": USER_AGENT},
            timeout=timeout,
            transport=transport,
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> WigleClient:
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def _get(self, path: str, params: Mapping[str, Any]) -> dict[str, Any]:
        response = self._client.get(path, params=dict(params))
        if response.status_code >= 400:
            raise WigleError(f"WiGLE {path} returned HTTP {response.status_code}: {response.text[:200]}")
        payload = response.json()
        if not isinstance(payload, dict):
            raise WigleError(f"WiGLE {path} returned non-object payload")
        return payload

    def _paginate(
        self,
        path: str,
        base_params: Mapping[str, Any],
        *,
        max_pages: int,
        page_delay: float,
    ) -> Iterator[dict[str, Any]]:
        params: dict[str, Any] = dict(base_params)
        requested = int(params.get("resultsPerPage", MAX_RESULTS_PER_PAGE))
        search_after: str | None = None
        lastnetid: str | None = None
        for _page in range(max_pages):
            if search_after:
                params["searchafter"] = search_after
                params.pop("lastnetid", None)
            elif lastnetid:
                # Legacy pagination fallback when the API returns no searchAfter.
                params["lastnetid"] = lastnetid
            payload = self._get(path, params)
            if payload.get("success") is False:
                raise WigleError(f"WiGLE {path} reported failure: {payload.get('message', '')}")
            results = payload.get("results") or []
            if not isinstance(results, list):
                raise WigleError(f"WiGLE {path} returned non-list results")
            yield from (item for item in results if isinstance(item, dict))
            if len(results) < requested:
                return
            cursor = payload.get("searchAfter")
            if isinstance(cursor, str) and cursor:
                search_after = cursor
            else:
                netid = results[-1].get("netid") if isinstance(results[-1], dict) else None
                if not isinstance(netid, str) or not netid:
                    return
                lastnetid = netid
            time.sleep(page_delay)
        LOGGER.warning("WiGLE search hit max_pages=%d before exhausting results", max_pages)

    def search(self, search: WigleSearch) -> Iterator[dict[str, Any]]:
        yield from self._paginate(
            SEARCH_PATH,
            search.initial_params(),
            max_pages=search.max_pages,
            page_delay=search.page_delay,
        )

    def bluetooth_search(self, search: WigleBluetoothSearch) -> Iterator[dict[str, Any]]:
        yield from self._paginate(
            BLUETOOTH_SEARCH_PATH,
            search.initial_params(),
            max_pages=search.max_pages,
            page_delay=search.page_delay,
        )

    def network_detail(self, netid: str) -> dict[str, Any]:
        """Fetch detail for one BSSID; primary /api/v2/network/{netid} with
        query-parameter detail fallback for swagger-declared deployments."""
        try:
            return self._get(f"/api/v2/network/{netid}", {})
        except WigleError as exc:
            if "HTTP 404" not in str(exc):
                raise
            return self._get("/api/v2/network/detail", {"netid": netid})
