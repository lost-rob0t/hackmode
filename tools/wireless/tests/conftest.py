from __future__ import annotations

from pathlib import Path

import pytest

from hackmode_wireless.transport import SchemaBoundary


@pytest.fixture
def boundary() -> SchemaBoundary:
    return SchemaBoundary.default()


@pytest.fixture
def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]
