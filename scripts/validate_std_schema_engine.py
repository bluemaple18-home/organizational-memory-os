#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema==4.25.1"]
# ///
"""以標準 JSON Schema Draft 2020-12 engine 驗證 STD-01／02 fixture。"""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATHS = (
    "規格/v0.1/raw-evidence-envelope.schema.json",
    "規格/v0.1/source-anchor.schema.json",
    "規格/v0.1/source-anchor-pdf-region-v1.schema.json",
    "規格/v0.1/source-anchor-markdown-text-v1.schema.json",
    "規格/v0.1/source-anchor-jira-cloud-entity-segment-v1.schema.json",
)
PROFILE_SCHEMAS = {
    "PDF_REGION_V1": "urn:omos:schema:source-anchor:pdf-region-v1:0.1.0",
    "MARKDOWN_TEXT_V1": "urn:omos:schema:source-anchor:markdown-text-v1:0.1.0",
    "JIRA_CLOUD_ENTITY_SEGMENT_V1": "urn:omos:schema:source-anchor:jira-cloud-entity-segment-v1:0.1.0",
}


def load_json(relative_path: str) -> dict:
    with (ROOT / relative_path).open(encoding="utf-8") as source:
        return json.load(source)


def apply_mutation(payload: dict, mutation: dict) -> None:
    keys = mutation["path"].split(".")
    parent = payload
    for key in keys[:-1]:
        parent = parent[key]
    if mutation["op"] == "delete":
        del parent[keys[-1]]
    else:
        parent[keys[-1]] = mutation["value"]


def rejected(validator: Draft202012Validator, instance: dict) -> bool:
    return bool(list(validator.iter_errors(instance)))


def validate_case_contract(case: dict, family: str, failures: list[str]) -> None:
    name = case.get("name", "<unnamed>")
    if case.get("validation_authority") not in {"JSON_SCHEMA", "RUBY_SEMANTIC"}:
        failures.append(f"{family}_NEGATIVE_AUTHORITY:{name}")
    if case.get("expected_result") != "REJECT":
        failures.append(f"{family}_NEGATIVE_EXPECTED_RESULT:{name}")
    if (
        case.get("validation_authority") == "RUBY_SEMANTIC"
        and case.get("schema_expected_result") != "ALLOW"
    ):
        failures.append(f"{family}_RUBY_SEMANTIC_SCHEMA_EXPECTED_RESULT:{name}")
    if "scenario" in case:
        expectations = case.get("instance_expectations")
        indexes = [item.get("instance_index") for item in expectations or []]
        expected_indexes = list(range(len(case["scenario"].get("envelopes", []))))
        if indexes != expected_indexes or any(
            item.get("expected_result") not in {"ALLOW", "REJECT"}
            for item in expectations or []
        ):
            failures.append(f"{family}_SCENARIO_INSTANCE_EXPECTATIONS:{name}")


def validate_raw_negatives(
    cases: list[dict], validator: Draft202012Validator, failures: list[str]
) -> tuple[list[str], list[str]]:
    schema_cases: list[str] = []
    ruby_cases: list[str] = []
    for case in cases:
        validate_case_contract(case, "STD01", failures)
        name = case["name"]
        if case.get("validation_authority") == "RUBY_SEMANTIC":
            instances = (
                case["scenario"].get("envelopes", [])
                if "scenario" in case
                else [case.get("invalid_envelope")]
            )
            schema_allowed = True
            for index, instance in enumerate(instances):
                if instance is None or rejected(validator, instance):
                    failures.append(f"STD01_RUBY_SEMANTIC_SCHEMA_REJECTED:{name}:{index}")
                    schema_allowed = False
            if schema_allowed:
                ruby_cases.append(name)
            continue
        schema_cases.append(name)
        invalid = case.get("invalid_envelope")
        if invalid is None or not rejected(validator, invalid):
            failures.append(f"STD01_JSON_SCHEMA_NOT_REJECTED:{name}")
    return schema_cases, ruby_cases


def validate_anchor_negatives(
    cases: list[dict], anchors_by_name: dict[str, dict], validators: dict[str, Draft202012Validator], failures: list[str]
) -> tuple[list[str], list[str]]:
    schema_cases: list[str] = []
    ruby_cases: list[str] = []
    for case in cases:
        validate_case_contract(case, "STD02", failures)
        name = case["name"]
        base = anchors_by_name.get(case.get("base_fixture"))
        if base is None:
            failures.append(f"STD02_NEGATIVE_BASE:{name}")
            continue
        mutated = copy.deepcopy(base)
        for mutation in case.get("mutations", []):
            apply_mutation(mutated, mutation)
        if case.get("validation_authority") == "RUBY_SEMANTIC":
            if rejected(validators[mutated["profile"]], mutated):
                failures.append(f"STD02_RUBY_SEMANTIC_SCHEMA_REJECTED:{name}")
            else:
                ruby_cases.append(name)
            continue
        schema_cases.append(name)
        if not rejected(validators[mutated["profile"]], mutated):
            failures.append(f"STD02_JSON_SCHEMA_NOT_REJECTED:{name}")
    return schema_cases, ruby_cases


def structural_relabel_probe(cases: list[dict], validator: Draft202012Validator) -> int:
    probe = copy.deepcopy(next(case for case in cases if case["name"] == "missing-raw-digest"))
    probe["validation_authority"] = "RUBY_SEMANTIC"
    probe["schema_expected_result"] = "ALLOW"
    failures: list[str] = []
    validate_raw_negatives([probe], validator, failures)
    expected = "STD01_RUBY_SEMANTIC_SCHEMA_REJECTED:missing-raw-digest:0"
    if expected in failures:
        print("STD schema engine validator FAIL")
        print(f"FAIL {expected}")
        return 1
    print("STD schema engine structural relabel probe unexpectedly accepted")
    return 2


def main() -> int:
    schemas = {document["$id"]: document for document in map(load_json, SCHEMA_PATHS)}
    registry = Registry().with_resources(
        (uri, Resource.from_contents(document)) for uri, document in schemas.items()
    )
    for document in schemas.values():
        Draft202012Validator.check_schema(document)

    raw_validator = Draft202012Validator(
        schemas["urn:omos:schema:raw-evidence-envelope:0.1.0"], registry=registry
    )
    profile_validators = {
        profile: Draft202012Validator(schemas[uri], registry=registry)
        for profile, uri in PROFILE_SCHEMAS.items()
    }

    raw_positive = load_json("規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json")
    anchor_positive = load_json("規格/v0.1/fixtures/std-02-source-anchor-positive-fixtures.json")
    raw_negative = load_json("規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json")
    anchor_negative = load_json("規格/v0.1/fixtures/std-02-source-anchor-negative-fixtures.json")

    if sys.argv[1:] == ["--probe-structural-relabel"]:
        return structural_relabel_probe(raw_negative["cases"], raw_validator)

    failures: list[str] = []
    for fixture in raw_positive["fixtures"]:
        if rejected(raw_validator, fixture["envelope"]):
            failures.append(f"STD01_POSITIVE_REJECTED:{fixture['name']}")
    for fixture in anchor_positive["fixtures"]:
        anchor = fixture["anchor"]
        if rejected(profile_validators[anchor["profile"]], anchor):
            failures.append(f"STD02_POSITIVE_REJECTED:{fixture['name']}")

    anchors_by_name = {
        fixture["name"]: fixture["anchor"] for fixture in anchor_positive["fixtures"]
    }
    raw_schema_cases, raw_ruby_cases = validate_raw_negatives(
        raw_negative["cases"], raw_validator, failures
    )
    anchor_schema_cases, anchor_ruby_cases = validate_anchor_negatives(
        anchor_negative["cases"], anchors_by_name, profile_validators, failures
    )

    if failures:
        print("STD schema engine validator FAIL")
        for failure in failures:
            print(f"FAIL {failure}")
        return 1

    print("STD schema engine validator PASS")
    print(f"STD01 JSON_SCHEMA coverage: {len(raw_schema_cases)}/{len(raw_schema_cases)}")
    print(
        "STD01 RUBY_SEMANTIC schema-allowed then excluded from schema rejection "
        f"coverage: {len(raw_ruby_cases)}"
    )
    print(f"STD02 JSON_SCHEMA coverage: {len(anchor_schema_cases)}/{len(anchor_schema_cases)}")
    print(
        "STD02 RUBY_SEMANTIC schema-allowed then excluded from schema rejection "
        f"coverage: {len(anchor_ruby_cases)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
