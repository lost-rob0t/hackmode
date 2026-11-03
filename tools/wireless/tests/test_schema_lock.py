"""Schema lock discipline.

The wireless dtypes are being minted in the canonical schema repo as the
0.10.1 release.  Until it lands, the repo-level lock holds
``{"status": "pending-0.10.1"}`` and the validation-pin checks skip.  When
the lock becomes concrete, this test fails closed until the pin checks are
restored against the canonical commit.

The lock lives outside this tree at
``../../schema/starintel-schema.lock.json`` relative to ``tools/wireless``
(the hackmode repo root's ``schema/`` directory).  It is added by a separate
repository change; while that change has not landed the lock file is absent
and this test skips loudly rather than fabricating a lock here.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

LOCK_RELATIVE_TO_PACKAGE_ROOT = ("schema", "starintel-schema.lock.json")


def test_schema_lock_pending_or_pinned(repo_root: Path) -> None:
    lock_path = repo_root.joinpath(*LOCK_RELATIVE_TO_PACKAGE_ROOT)
    if not lock_path.is_file():
        pytest.skip(
            "schema/starintel-schema.lock.json is added by a separate change; "
            "this test fails closed once the lock exists"
        )
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    status = lock.get("status")
    if status == "pending-0.10.1":
        # Validation-pin checks are skipped while the canonical 0.10.1
        # release is being minted (see README "Schema lock").
        return
    # Fail closed: a concrete lock must carry the canonical authority chain
    # and the supplemental validators must be re-verified against it.
    assert lock.get("release_version") == "0.10.1", lock
    assert lock.get("schema_version") == "0.9.0", lock
    assert lock.get("canonical_repository"), lock
    assert lock.get("canonical_commit"), lock
    raise AssertionError(
        "lock is no longer pending but the pin checks were not restored; "
        "run the canonical schema-release checker and wire conformance here"
    )
