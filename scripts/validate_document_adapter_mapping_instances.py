#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema==4.25.1", "rfc3339-validator==0.1.4"]
# ///
"""repo #2 / Document Adapter Mapping -- instance_validation gate.

以標準 JSON Schema Draft 2020-12 engine 驗證每個 positive fixture 投影出的
RawEvidenceEnvelope / SourceAnchor / NormalizedDocumentBlock 是否為 locked
target schema 的合法 instance,並確認每個 instance_negative case 會被拒。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATHS = (
    "規格/v0.1/raw-evidence-envelope.schema.json",
    "規格/v0.1/source-anchor.schema.json",
    "規格/v0.1/source-anchor-pdf-region-v1.schema.json",
    "規格/v0.1/source-anchor-markdown-text-v1.schema.json",
    "規格/v0.1/normalized-document-block.schema.json",
)
RAW_EVIDENCE_ID = "urn:omos:schema:raw-evidence-envelope:0.1.0"
BLOCK_ID = "urn:omos:schema:normalized-document-block:0.1.0"
PROFILE_SCHEMA_ID_BY_KIND = {
    "PDF": "urn:omos:schema:source-anchor:pdf-region-v1:0.1.0",
    "MARKDOWN": "urn:omos:schema:source-anchor:markdown-text-v1:0.1.0",
}
TARGET_SCHEMA_ID = {
    "raw-evidence-envelope.schema.json": RAW_EVIDENCE_ID,
    "normalized-document-block.schema.json": BLOCK_ID,
    "source-anchor-pdf-region-v1.schema.json": PROFILE_SCHEMA_ID_BY_KIND["PDF"],
    "source-anchor-markdown-text-v1.schema.json": PROFILE_SCHEMA_ID_BY_KIND["MARKDOWN"],
}
FORMAT_CHECKER = FormatChecker()

POSITIVE_FIXTURE = "規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json"
INSTANCE_NEGATIVE_FIXTURE = "規格/v0.1/fixtures/document-adapter-mapping-instance-negative-fixtures.json"


class DuplicateKeyError(ValueError):
    pass


def reject_duplicate_pairs(pairs):
    payload = {}
    for key, value in pairs:
        if key in payload:
            raise DuplicateKeyError(key)
        payload[key] = value
    return payload


def load_json(relative_path: str):
    with (ROOT / relative_path).open(encoding="utf-8") as source:
        return json.load(source, object_pairs_hook=reject_duplicate_pairs)


def main() -> int:
    schemas = {doc["$id"]: doc for doc in map(load_json, SCHEMA_PATHS)}
    registry = Registry().with_resources(
        (uri, Resource.from_contents(doc)) for uri, doc in schemas.items()
    )
    for doc in schemas.values():
        Draft202012Validator.check_schema(doc)

    validators = {
        uri: Draft202012Validator(doc, registry=registry, format_checker=FORMAT_CHECKER)
        for uri, doc in schemas.items()
    }

    failures: list[str] = []

    positive = load_json(POSITIVE_FIXTURE)
    for case in positive["document_mapping_cases"]:
        name = case["case_id"]
        kind = case["source_kind"]

        errors = list(validators[RAW_EVIDENCE_ID].iter_errors(case["raw_evidence_instance"]))
        if errors:
            failures.append(f"POSITIVE_RAW_EVIDENCE_INVALID:{name}:{errors[0].message}")

        anchor_validator = validators[PROFILE_SCHEMA_ID_BY_KIND[kind]]
        errors = list(anchor_validator.iter_errors(case["source_anchor_instance"]))
        if errors:
            failures.append(f"POSITIVE_SOURCE_ANCHOR_INVALID:{name}:{errors[0].message}")

        for index, block in enumerate(case["block_instances"]):
            errors = list(validators[BLOCK_ID].iter_errors(block))
            if errors:
                failures.append(f"POSITIVE_BLOCK_INVALID:{name}[{index}]:{errors[0].message}")

    negative = load_json(INSTANCE_NEGATIVE_FIXTURE)
    for case in negative["instance_negative_cases"]:
        name = case["case_id"]
        target = case["target_schema"]
        schema_id = TARGET_SCHEMA_ID.get(target)
        if schema_id is None:
            failures.append(f"INSTANCE_NEGATIVE_UNKNOWN_TARGET:{name}:{target}")
            continue
        if case.get("expected_result") != "REJECT":
            failures.append(f"INSTANCE_NEGATIVE_EXPECTED_RESULT:{name}")
        errors = list(validators[schema_id].iter_errors(case["instance"]))
        if not errors:
            failures.append(f"INSTANCE_NEGATIVE_UNEXPECTEDLY_VALID:{name}")

    if failures:
        print("document adapter mapping instance validation FAIL")
        for line in failures:
            print(f"FAIL {line}")
        return 1
    print(
        "document adapter mapping instance validation PASS "
        f"(positive_instances={sum(2 + len(c['block_instances']) for c in positive['document_mapping_cases'])}, "
        f"instance_negatives={len(negative['instance_negative_cases'])})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
