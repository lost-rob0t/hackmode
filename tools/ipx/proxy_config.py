#!/usr/bin/env python3
"""Emit client configuration for a running canonical IPX capture proxy.

This helper does not start a proxy, mutate trust stores, or write evidence. It
only tells clients how to route HTTP(S) traffic to an already supervised
capture listener.
"""

from __future__ import annotations

import argparse
import json
import shlex
from dataclasses import dataclass
from typing import Mapping


@dataclass(frozen=True, slots=True)
class ProxyConfig:
    host: str = "127.0.0.1"
    port: int = 8080
    ca_cert: str | None = None

    def __post_init__(self) -> None:
        host = self.host.strip()
        if not host:
            raise ValueError("proxy host must not be empty")
        if not 1 <= self.port <= 65535:
            raise ValueError("proxy port must be between 1 and 65535")
        object.__setattr__(self, "host", host)
        if self.ca_cert is not None and not self.ca_cert.strip():
            raise ValueError("CA certificate path must not be empty")

    @property
    def authority(self) -> str:
        host = self.host
        if host.startswith("[") and host.endswith("]"):
            return f"{host}:{self.port}"
        if ":" in host:
            return f"[{host}]:{self.port}"
        return f"{host}:{self.port}"

    @property
    def proxy_url(self) -> str:
        return f"http://{self.authority}"

    def environment(self) -> dict[str, str]:
        env = {
            "HTTP_PROXY": self.proxy_url,
            "HTTPS_PROXY": self.proxy_url,
            "ALL_PROXY": self.proxy_url,
        }
        if self.ca_cert:
            env.update(
                {
                    "SSL_CERT_FILE": self.ca_cert,
                    "REQUESTS_CA_BUNDLE": self.ca_cert,
                    "CURL_CA_BUNDLE": self.ca_cert,
                    "NODE_EXTRA_CA_CERTS": self.ca_cert,
                }
            )
        return env


def render_env(values: Mapping[str, str]) -> str:
    return "\n".join(
        f"export {name}={shlex.quote(value)}" for name, value in values.items()
    )


def render_json(config: ProxyConfig) -> str:
    payload = {
        "proxy_url": config.proxy_url,
        "host": config.host,
        "port": config.port,
        "ca_cert": config.ca_cert,
        "environment": config.environment(),
    }
    return json.dumps(payload, indent=2, sort_keys=True)


def render_curl(config: ProxyConfig) -> str:
    parts = ["curl", "--proxy", config.proxy_url]
    if config.ca_cert:
        parts.extend(["--cacert", config.ca_cert])
    return " ".join(shlex.quote(part) for part in parts)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit client settings for the canonical IPX HTTPS proxy"
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--ca-cert")
    parser.add_argument(
        "--format",
        choices=("env", "json", "curl"),
        default="env",
        dest="output_format",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        config = ProxyConfig(args.host, args.port, args.ca_cert)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    if args.output_format == "json":
        output = render_json(config)
    elif args.output_format == "curl":
        output = render_curl(config)
    else:
        output = render_env(config.environment())
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
