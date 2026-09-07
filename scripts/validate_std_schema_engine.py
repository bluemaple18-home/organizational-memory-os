#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema==4.25.1"]
# ///
"""以標準 JSON Schema Draft 2020-12 engine 驗證 STD-01／02／03 fixture。"""

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
    "規格/v0.1/normalized-document.schema.json",
    "規格/v0.1/normalized-document-block.schema.json",
)
PROFILE_SCHEMAS = {
    "PDF_REGION_V1": "urn:omos:schema:source-anchor:pdf-region-v1:0.1.0",
    "MARKDOWN_TEXT_V1": "urn:omos:schema:source-anchor:markdown-text-v1:0.1.0",
    "JIRA_CLOUD_ENTITY_SEGMENT_V1": "urn:omos:schema:source-anchor:jira-cloud-entity-segment-v1:0.1.0",
}


class DuplicateKeyError(ValueError):
    pass


def reject_duplicate_object_pairs(pairs: list[tuple[str, object]]) -> dict:
    payload: dict = {}
    for key, value in pairs:
        if key in payload:
            raise DuplicateKeyError(key)
        payload[key] = value
    return payload


def load_json(relative_path: str) -> dict:
    with (ROOT / relative_path).open(encoding="utf-8") as source:
        return json.load(source, object_pairs_hook=reject_duplicate_object_pairs)


def apply_mutation(payload: dict, mutation: dict) -> None:
    keys = mutation["path"].split(".")
    parent = payload
    for key in keys[:-1]:
        parent = parent[int(key)] if isinstance(parent, list) else parent[key]
    if mutation["op"] == "delete":
        if isinstance(parent, list):
            del parent[int(keys[-1])]
        else:
            del parent[keys[-1]]
    else:
        if isinstance(parent, list):
            parent[int(keys[-1])] = mutation["value"]
        else:
            parent[keys[-1]] = mutation["value"]


def rejected(validator: Draft202012Validator, instance: dict) -> bool:
    return bool(list(validator.iter_errors(instance)))


def schema_error_pairs(validator: Draft202012Validator, instance: dict) -> set[tuple[str, str]]:
    return {
        ("/" + "/".join(map(str, error.absolute_path)), error.validator)
        for error in validator.iter_errors(instance)
    }


def expected_schema_error_pairs(case: dict, family: str, failures: list[str]) -> set[tuple[str, str]]:
    name = case["name"]
    expected_errors = case.get("expected_schema_errors")
    if not isinstance(expected_errors, list) or not expected_errors:
        failures.append(f"{family}_JSON_SCHEMA_EXPECTED_ERRORS:{name}")
        return set()
    pairs: set[tuple[str, str]] = set()
    for expected in expected_errors:
        if (
            not isinstance(expected, dict)
            or not isinstance(expected.get("path"), str)
            or not isinstance(expected.get("validator"), str)
        ):
            failures.append(f"{family}_JSON_SCHEMA_EXPECTED_ERROR_SHAPE:{name}")
            return set()
        pairs.add((expected["path"], expected["validator"]))
    return pairs


def validate_schema_error_pairs(
    actual_pairs: set[tuple[str, str]],
    expected_pairs: set[tuple[str, str]],
    case_name: str,
    family: str,
    failures: list[str],
) -> None:
    if actual_pairs == expected_pairs:
        return
    missing = sorted(expected_pairs - actual_pairs)
    extra = sorted(actual_pairs - expected_pairs)
    failures.append(
        f"{family}_JSON_SCHEMA_ERROR_PAIRS_MISMATCH:"
        f"{case_name}:missing={missing}:extra={extra}"
    )


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
        pairs = schema_error_pairs(validator, invalid) if invalid is not None else set()
        if invalid is None or not pairs:
            failures.append(f"STD01_JSON_SCHEMA_NOT_REJECTED:{name}")
            continue
        validate_schema_error_pairs(
            pairs,
            expected_schema_error_pairs(case, "STD01", failures),
            name,
            "STD01",
            failures,
        )
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
        pairs = schema_error_pairs(validators[mutated["profile"]], mutated)
        if not pairs:
            failures.append(f"STD02_JSON_SCHEMA_NOT_REJECTED:{name}")
            continue
        validate_schema_error_pairs(
            pairs,
            expected_schema_error_pairs(case, "STD02", failures),
            name,
            "STD02",
            failures,
        )
    return schema_cases, ruby_cases


def apply_document_mutations(bundle: dict, mutations: list[dict]) -> list[dict]:
    mutated_targets = []
    for mutation in mutations:
        target = mutation["target"]
        if target == "root":
            apply_mutation(bundle["root"], mutation)
            mutated_targets.append(bundle["root"])
        elif target == "block":
            block = bundle["blocks"][mutation["index"]]
            apply_mutation(block, mutation)
            mutated_targets.append(block)
        else:
            raise KeyError(target)
    return mutated_targets


def validate_document_negatives(
    cases: list[dict],
    documents_by_name: dict[str, dict],
    root_validator: Draft202012Validator,
    block_validator: Draft202012Validator,
    failures: list[str],
) -> tuple[list[str], list[str]]:
    schema_cases: list[str] = []
    ruby_cases: list[str] = []
    for case in cases:
        validate_case_contract(case, "STD03", failures)
        name = case["name"]
        base = documents_by_name.get(case.get("base_fixture"))
        if base is None:
            failures.append(f"STD03_NEGATIVE_BASE:{name}")
            continue
        mutated = copy.deepcopy(base)
        mutated_targets = apply_document_mutations(mutated, case.get("mutations", []))
        if case.get("validation_authority") == "RUBY_SEMANTIC":
            schema_rejected = rejected(root_validator, mutated["root"]) or any(
                rejected(block_validator, block) for block in mutated["blocks"]
            )
            if schema_rejected:
                failures.append(f"STD03_RUBY_SEMANTIC_SCHEMA_REJECTED:{name}")
            else:
                ruby_cases.append(name)
            continue
        schema_cases.append(name)
        pairs: set[tuple[str, str]] = set()
        targets = mutated_targets or [mutated["root"]]
        for target in targets:
            validator = root_validator if target is mutated["root"] else block_validator
            pairs |= schema_error_pairs(validator, target)
        if not pairs:
            failures.append(f"STD03_JSON_SCHEMA_NOT_REJECTED:{name}")
            continue
        validate_schema_error_pairs(
            pairs,
            expected_schema_error_pairs(case, "STD03", failures),
            name,
            "STD03",
            failures,
        )
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


def unrelated_rejection_probe(cases: list[dict], validator: Draft202012Validator) -> int:
    probe = copy.deepcopy(next(case for case in cases if case["name"] == "non-i-json-without-canonicalization-gap"))
    probe["invalid_envelope"]["quality_gaps"] = [
        {
            "code": "CANONICALIZATION_UNAVAILABLE",
            "severity": "LOW",
            "detail": "Non-I-JSON canonicalization unavailable."
        }
    ]
    probe["invalid_envelope"]["payload"]["payload_ref"] = ""
    failures: list[str] = []
    validate_raw_negatives([probe], validator, failures)
    expected_prefix = (
        "STD01_JSON_SCHEMA_ERROR_PAIRS_MISMATCH:"
        "non-i-json-without-canonicalization-gap:"
    )
    if any(failure.startswith(expected_prefix) for failure in failures):
        print("STD schema engine validator FAIL")
        print(f"FAIL {expected_prefix}extra")
        return 1
    print("STD schema engine unrelated rejection probe unexpectedly accepted")
    return 2


def duplicate_json_probe() -> int:
    probe_path = "inline duplicate-key JSON"
    try:
        json.loads('{"schema_version":"x","schema_version":"y"}', object_pairs_hook=reject_duplicate_object_pairs)
    except DuplicateKeyError as error:
        print("STD schema engine validator FAIL")
        print(f"FAIL DUPLICATE_JSON_KEY:{probe_path}:{error}")
        return 1
    print("STD schema engine duplicate JSON probe unexpectedly accepted")
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
    normalized_document_validator = Draft202012Validator(
        schemas["urn:omos:schema:normalized-document:0.1.0"], registry=registry
    )
    normalized_block_validator = Draft202012Validator(
        schemas["urn:omos:schema:normalized-document-block:0.1.0"], registry=registry
    )
    profile_validators = {
        profile: Draft202012Validator(schemas[uri], registry=registry)
        for profile, uri in PROFILE_SCHEMAS.items()
    }

    raw_positive = load_json("規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json")
    anchor_positive = load_json("規格/v0.1/fixtures/std-02-source-anchor-positive-fixtures.json")
    raw_negative = load_json("規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json")
    anchor_negative = load_json("規格/v0.1/fixtures/std-02-source-anchor-negative-fixtures.json")
    document_positive = load_json("規格/v0.1/fixtures/std-03-normalized-document-positive-fixtures.json")
    document_negative = load_json("規格/v0.1/fixtures/std-03-normalized-document-negative-fixtures.json")

    if sys.argv[1:] == ["--probe-structural-relabel"]:
        return structural_relabel_probe(raw_negative["cases"], raw_validator)
    if sys.argv[1:] == ["--probe-unrelated-json-schema"]:
        return unrelated_rejection_probe(raw_negative["cases"], raw_validator)
    if sys.argv[1:] == ["--probe-duplicate-json"]:
        return duplicate_json_probe()

    failures: list[str] = []
    for fixture in raw_positive["fixtures"]:
        if rejected(raw_validator, fixture["envelope"]):
            failures.append(f"STD01_POSITIVE_REJECTED:{fixture['name']}")
    for fixture in anchor_positive["fixtures"]:
        anchor = fixture["anchor"]
        if rejected(profile_validators[anchor["profile"]], anchor):
            failures.append(f"STD02_POSITIVE_REJECTED:{fixture['name']}")
    for fixture in document_positive["fixtures"]:
        if rejected(normalized_document_validator, fixture["root"]):
            failures.append(f"STD03_ROOT_POSITIVE_REJECTED:{fixture['name']}")
        for index, block in enumerate(fixture["blocks"]):
            if rejected(normalized_block_validator, block):
                failures.append(f"STD03_BLOCK_POSITIVE_REJECTED:{fixture['name']}:{index}")

    anchors_by_name = {
        fixture["name"]: fixture["anchor"] for fixture in anchor_positive["fixtures"]
    }
    raw_schema_cases, raw_ruby_cases = validate_raw_negatives(
        raw_negative["cases"], raw_validator, failures
    )
    anchor_schema_cases, anchor_ruby_cases = validate_anchor_negatives(
        anchor_negative["cases"], anchors_by_name, profile_validators, failures
    )
    documents_by_name = {
        fixture["name"]: fixture for fixture in document_positive["fixtures"]
    }
    document_schema_cases, document_ruby_cases = validate_document_negatives(
        document_negative["cases"],
        documents_by_name,
        normalized_document_validator,
        normalized_block_validator,
        failures,
    )

    if failures:
        print("STD schema engine validator FAIL")
        for failure in failures:
            print(f"FAIL {failure}")
        return 1

    print("STD schema engine validator PASS")
    print(
        "STD01 coverage: "
        f"json_schema_tested={len(raw_schema_cases)} "
        f"json_schema_passed={len(raw_schema_cases)} "
        f"ruby_semantic_excluded={len(raw_ruby_cases)}"
    )
    print(
        "STD02 coverage: "
        f"json_schema_tested={len(anchor_schema_cases)} "
        f"json_schema_passed={len(anchor_schema_cases)} "
        f"ruby_semantic_excluded={len(anchor_ruby_cases)}"
    )
    print(
        "STD03 coverage: "
        f"json_schema_tested={len(document_schema_cases)} "
        f"json_schema_passed={len(document_schema_cases)} "
        f"ruby_semantic_excluded={len(document_ruby_cases)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
