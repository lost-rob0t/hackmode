"""Actor-manifest emission tests."""

from __future__ import annotations

import pytest

from hackmode_wireless.manifests import (
    ACTOR_MANIFESTS,
    actor_manifest_document,
    all_actor_manifest_documents,
    manifest_ids_for_actor_names,
)
from hackmode_wireless.transport import SchemaBoundary


def test_registry_has_both_actors() -> None:
    assert sorted(ACTOR_MANIFESTS) == ["kismet", "wigle"]


def test_manifest_documents_validate(boundary: SchemaBoundary) -> None:
    for document in all_actor_manifest_documents(now="2026-09-19T00:00:00+00:00"):
        boundary.validate(document)


def test_manifest_document_shape(boundary: SchemaBoundary) -> None:
    document = actor_manifest_document("wigle", now="2026-09-19T00:00:00+00:00")
    assert document["_id"] == "starintel:actor-manifest:wigle"
    assert document["dtype"] == "actor-manifest"
    assert document["data"]["actor"] == "wigle"
    contract = document["extensions"]["starintel.actor_manifest.v1"]
    assert contract["actor_type"] == "collector"
    assert contract["entrypoint"].startswith("hackmode_wireless.")
    assert "wireless-network" in contract["output_dtypes"]
    boundary.validate(document)


def test_manifest_unknown_actor() -> None:
    with pytest.raises(KeyError, match="unknown actor manifest"):
        actor_manifest_document("nope")


def test_manifest_ids_for_actor_names() -> None:
    assert manifest_ids_for_actor_names(["wigle", "kismet", "unknown"]) == ("kismet", "wigle")


def test_manifest_deterministic_ids() -> None:
    one = actor_manifest_document("kismet", now="2026-09-19T00:00:00+00:00")
    two = actor_manifest_document("kismet", now="2027-01-01T00:00:00+00:00")
    assert one["_id"] == two["_id"]
