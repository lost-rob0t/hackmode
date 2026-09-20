#!/usr/bin/env bash
# Derive the full Kali tool catalog (every tool, every category) from Kali's
# own package metadata. Run on a Kali host or any host with the Kali archive
# configured. Writes full-<arch>.json beside the seed; never mutates seed.json.
set -euo pipefail

outdir="$(cd "$(dirname "$0")" && pwd)"
arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
out="$outdir/full-$arch.json"
tmp="$(mktemp)"

for meta in $(python3 -c 'import json;print(" ".join(c["metapackage"] for c in json.load(open("'"$outdir"'/seed.json"))["categories"]))'); do
  echo "CATEGORY $meta" >> "$tmp"
  apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$meta" 2>/dev/null |
    awk '/^\s*Depends:/ { sub(/^\s*Depends: /,""); print }' >> "$tmp"
done

python3 - "$tmp" "$out" "$outdir/seed.json" <<'PY'
import json, sys

lines, out_path, seed_path = sys.argv[1], sys.argv[2], sys.argv[3]
seed = json.load(open(seed_path))
known = {t["name"].lower() for t in seed.get("tools", [])}

result, category = [], None
for raw in open(lines):
    line = raw.strip()
    if line.startswith("CATEGORY "):
        category = line.split(" ", 1)[1]
        continue
    if not line or line.startswith("<"):
        continue
    name = line.split()[0]
    result.append({
        "tool_id": name,
        "name": name,
        "category": category,
        "mode": "unknown",
        "wrapper_status": "first-party" if name.lower() in known else "none",
        "seeded": name.lower() in known,
    })

json.dump({
    "schema": "hackmode-kali-registry-full/1",
    "derived_from": "apt-cache depends over kali-tools-* metapackages",
    "tool_count": len(result),
    "tools": result,
}, open(out_path, "w"), indent=2)
print(f"wrote {out_path} with {len(result)} tools")
PY

rm -f "$tmp"
