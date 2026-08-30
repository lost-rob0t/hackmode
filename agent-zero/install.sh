#!/usr/bin/env sh
set -eu

A0_USR="${1:-/a0/usr}"
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

mkdir -p "$A0_USR/agents"
for profile in hackmode-rage-database hackmode-rage-hackpert; do
  rm -rf "$A0_USR/agents/$profile"
  cp -R "$ROOT/agent-zero/usr/agents/$profile" "$A0_USR/agents/$profile"
done

printf 'Installed Hackmode Auto-RAGE profiles into %s/agents\n' "$A0_USR"
printf 'Profiles: hackmode-rage-database, hackmode-rage-hackpert\n'
