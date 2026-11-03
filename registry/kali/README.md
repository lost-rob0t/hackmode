# Kali tool registry

Machine-readable registry of the Kali Linux tool catalog that first-party
recon capabilities are tracked against. Category names mirror the official
Kali metapackages (verified against <https://www.kali.org/docs/general-use/metapackages/>
and the metapackage makeover announcement; both list the same category set).

## Layout

- `seed.json` — curated seed: every official category plus seeded tools for
  the recon-relevant ones. Record shape is deliberately minimal:
  `{ "tool_id", "name", "category", "mode", "wrapper_status" }` where
  `mode` is `passive | active` and `wrapper_status` is
  `first-party | designed | planned | none`.
- `build-registry.sh` — derives the FULL tool list (every tool in every
  category) from Kali's own package metadata by walking
  `apt-cache depends` over the category metapackages. Run it on a Kali host
  (or any host with the Kali archive configured); it writes
  `full-<arch>.json` next to the seed and never mutates the seed.

## Coverage rule

"Support every tool in Kali" means: every category is present in the seed,
and every tool is derivable deterministically via the build script. A tool
only gets a wrapper_status above `none` when a first-party capability
actually emits StarIntel documents for it.

## Provenance

Package metadata in the Kali archive is Debian package metadata; the
category list is from kali.org's documentation pages. Cite the Kali
snapshot date whenever a derived `full-*.json` is committed.
