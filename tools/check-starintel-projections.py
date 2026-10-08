"""Validate actual Lisp projection output against the pinned generated schema."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "spec/vendor/starintel-0.10.1/generated/schema.json"
EXPECTED_DTYPES = {"domain", "host", "url", "operation", "research-node",
                   "http-transaction", "web-capture"}


def validator_for(schema: dict, dtype: str) -> Draft202012Validator:
    name = "".join(part.capitalize() for part in dtype.split("-"))
    if name not in schema["$defs"]:
        raise ValueError(f"unknown canonical dtype: {dtype}")
    return Draft202012Validator(
        {"$ref": f"#/$defs/{name}", "$defs": schema["$defs"]},
        format_checker=FormatChecker(),
    )


def main() -> None:
    schema = json.loads(SCHEMA.read_text())
    Draft202012Validator.check_schema(schema)
    documents = json.loads(Path(sys.argv[1]).read_text())
    seen = set()
    for document in documents:
        dtype = document["dtype"]
        if document["schemaVersion"] != "0.10.1":
            raise ValueError("wrong emitted schemaVersion")
        validator_for(schema, dtype).validate(document)
        seen.add(dtype)
    if not EXPECTED_DTYPES.issubset(seen):
        raise ValueError(f"missing projection coverage: {EXPECTED_DTYPES - seen}")

    # Independent negative controls prove the schema rejects the old wire
    # shape and malformed nested values, beyond Lisp's top-level checks.
    examples = {document["dtype"]: document for document in documents}
    invalid = []
    legacy = copy.deepcopy(examples["domain"])
    legacy["_id"] = legacy.pop("id")
    legacy["schema_version"] = legacy.pop("schemaVersion")
    invalid.append(legacy)
    wrapped = copy.deepcopy(examples["domain"])
    wrapped["data"] = {"name": wrapped.pop("name")}
    invalid.append(wrapped)
    references = copy.deepcopy(examples["domain"])
    references["resolvedAddresses"] = ["1.2.3.4"]
    invalid.append(references)
    phase = copy.deepcopy(examples["operation"])
    phase["phases"] = [{"name": "recon", "status": "active"}]
    invalid.append(phase)
    status = copy.deepcopy(examples["research-node"])
    status["status"] = "active"
    invalid.append(status)
    for document in invalid:
        if validator_for(schema, document["dtype"]).is_valid(document):
            raise ValueError("canonical negative control unexpectedly passed")
    print(f"Canonical StarIntel 0.10.1: {len(documents)} projections validated; "
          f"{len(invalid)} malformed controls rejected")


if __name__ == "__main__":
    main()
