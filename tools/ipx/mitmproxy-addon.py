"""Lossless operation-scoped HTTP evidence writer for mitmproxy.

This addon has one job: append versioned source-evidence records to the configured
IPX spool. It intentionally has no database, KB, or remote-ingest authority.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
from typing import Any

from mitmproxy import ctx, http

SCHEMA = "hackmode-ipx-http"


def _b64(value: bytes | None) -> str:
    return base64.b64encode(value or b"").decode("ascii")


def _raw_headers(headers: http.Headers) -> list[list[str]]:
    return [[_b64(name), _b64(value)] for name, value in headers.fields]


def _connection_metadata(flow: http.HTTPFlow) -> dict[str, Any]:
    server = flow.server_conn
    client = flow.client_conn
    return {
        "client_peername": list(client.peername) if client.peername else None,
        "server_address": list(server.address) if server.address else None,
        "server_sni": server.sni,
        "server_alpn": server.alpn.decode("ascii", "backslashreplace") if server.alpn else None,
        "server_cipher": server.cipher,
        "tls_version": server.tls_version,
    }


class IPXSpoolAddon:
    def load(self, loader: Any) -> None:
        loader.add_option("hackmode_operation_id", str, "", "Hackmode operation identity")
        loader.add_option("hackmode_capture_session_id", str, "", "Hackmode capture session identity")
        loader.add_option("hackmode_spool_id", str, "", "Hackmode spool identity")
        loader.add_option("hackmode_spool_path", str, "", "Append-only IPX spool path")
        loader.add_option("hackmode_ipx_version", int, 1, "IPX record format version")

    def running(self) -> None:
        required = {
            "hackmode_operation_id": ctx.options.hackmode_operation_id,
            "hackmode_capture_session_id": ctx.options.hackmode_capture_session_id,
            "hackmode_spool_id": ctx.options.hackmode_spool_id,
            "hackmode_spool_path": ctx.options.hackmode_spool_path,
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise RuntimeError(f"Missing required IPX options: {', '.join(missing)}")
        parent = os.path.dirname(os.path.abspath(ctx.options.hackmode_spool_path))
        os.makedirs(parent, exist_ok=True)

    def response(self, flow: http.HTTPFlow) -> None:
        request = flow.request
        response = flow.response
        if response is None:
            return

        session = ctx.options.hackmode_capture_session_id
        exchange_id = hashlib.sha256(f"{session}\0{flow.id}".encode("utf-8")).hexdigest()
        record = {
            "schema": SCHEMA,
            "version": ctx.options.hackmode_ipx_version,
            "operation_id": ctx.options.hackmode_operation_id,
            "capture_session_id": session,
            "spool_id": ctx.options.hackmode_spool_id,
            "exchange_id": exchange_id,
            "correlation_id": flow.id,
            "timestamp_start": flow.timestamp_start,
            "timestamp_end": flow.timestamp_end,
            "request": {
                "method": request.method,
                "scheme": request.scheme,
                "host": request.host,
                "port": request.port,
                "path": request.path,
                "http_version": request.http_version,
                "headers_raw_b64": _raw_headers(request.headers),
                "body_raw_b64": _b64(request.raw_content),
            },
            "response": {
                "status_code": response.status_code,
                "reason": response.reason,
                "http_version": response.http_version,
                "headers_raw_b64": _raw_headers(response.headers),
                "body_raw_b64": _b64(response.raw_content),
            },
            "connection": _connection_metadata(flow),
            "provider": {
                "name": "mitmproxy",
                "addon_schema": SCHEMA,
                "addon_version": 1,
            },
        }
        encoded = (json.dumps(record, separators=(",", ":"), sort_keys=True) + "\n").encode("utf-8")
        path = ctx.options.hackmode_spool_path
        with open(path, "ab", buffering=0) as spool:
            spool.write(encoded)
            os.fsync(spool.fileno())


addons = [IPXSpoolAddon()]
