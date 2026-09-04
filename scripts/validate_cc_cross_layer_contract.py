#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""驗證 PersonalMemoryCandidate 到已解析 STD fixture 的跨層閉環。"""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MUTATION_TARGETS = {"candidate", "support", "binding", "raw", "anchor"}


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


def changed_paths(left: object, right: object, prefix: str = "") -> list[str]:
    if isinstance(left, dict) and isinstance(right, dict):
        keys = left.keys() | right.keys()
        return [
            path
            for key in keys
            for path in changed_paths(left.get(key), right.get(key), f"{prefix}.{key}".strip("."))
        ]
    return [] if left == right else [prefix]


def failure_codes(case: dict, raw: dict | None, anchor: dict | None) -> list[str]:
    candidate = case["candidate"]
    support = case["support_link"]
    binding = case["access_binding"]
    failures: list[str] = []

    if raw is None or support.get("evidence_ref") != raw.get("evidence_ref") or (anchor or {}).get("evidence_ref") != raw.get("evidence_ref"):
        failures.append("SUPPORT_EVIDENCE_REF")
    if anchor is None or not support.get("source_anchor_ref") or support.get("source_anchor_ref") != anchor.get("anchor_ref"):
        failures.append("SUPPORT_ANCHOR_REF")
    if candidate.get("support_link_refs") != [support.get("link_id")] or support.get("target_ref") != candidate.get("candidate_id"):
        failures.append("CANDIDATE_SUPPORT_REF")
    if candidate.get("tenant_id") != support.get("tenant_id") or candidate.get("tenant_id") != (raw or {}).get("tenant_id"):
        failures.append("TENANT_ALIGNMENT")
    if candidate.get("employee_owner_ref") != support.get("employee_owner_ref") or candidate.get("employee_owner_ref") != support.get("target_employee_owner_ref"):
        failures.append("OWNER_ALIGNMENT")
    if (anchor or {}).get("source_identity") != (raw or {}).get("source_identity") or (anchor or {}).get("source_version") != (raw or {}).get("source_version"):
        failures.append("SOURCE_IDENTITY_VERSION")
    representation = (anchor or {}).get("representation", {})
    payload = (raw or {}).get("payload", {})
    digests = (raw or {}).get("digests", {})
    if representation.get("source_payload_ref") != payload.get("payload_ref") or representation.get("source_payload_digest") != digests.get("raw_digest") or representation.get("representation_digest") != digests.get("raw_digest"):
        failures.append("REPRESENTATION_DIGEST")
    if (anchor or {}).get("access", {}).get("acl_snapshot_ref") != (raw or {}).get("access", {}).get("acl_snapshot_ref") or binding.get("source_acl_snapshot_ref") != (raw or {}).get("access", {}).get("acl_snapshot_ref") or candidate.get("governance", {}).get("acl_ref") != binding.get("candidate_acl_ref"):
        failures.append("ACL_BINDING")
    if binding.get("source_visibility_scope_refs") != (raw or {}).get("access", {}).get("visibility_scope_refs") or candidate.get("governance", {}).get("visibility_scope") != binding.get("candidate_visibility_scope") or binding.get("scope_relation") != "SELF_ONLY_SUBSET_OF_SOURCE":
        failures.append("VISIBILITY_SCOPE")
    if (anchor or {}).get("source_availability") != "AVAILABLE" or (anchor or {}).get("resolution", {}).get("status") != "EXACT_MATCH" or support.get("anchor_resolution") != "EXACT_MATCH":
        failures.append("RESOLUTION_AVAILABILITY")
    material = support.get("support_material", {})
    if material.get("kind") != "EXACT_SOURCE_ANCHOR" or material.get("exact_quote") != (anchor or {}).get("quote", {}).get("exact"):
        failures.append("SUPPORT_MATERIAL")
    return failures


def resolve_case(case: dict, raw_by_name: dict[str, dict], anchor_by_name: dict[str, dict]) -> tuple[dict, dict | None, dict | None]:
    raw = raw_by_name.get(case.get("raw_evidence_fixture_ref"))
    anchor = anchor_by_name.get(case.get("anchor_fixture_ref"))
    return copy.deepcopy(case), copy.deepcopy(raw), copy.deepcopy(anchor)


def main() -> int:
    fixture = load_json("規格/v0.1/fixtures/cc-schema-foundation-cross-layer-fixtures.json")
    raw_fixture = load_json("規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json")
    anchor_fixture = load_json("規格/v0.1/fixtures/std-02-source-anchor-positive-fixtures.json")
    raw_by_name = {item["name"]: item["envelope"] for item in raw_fixture["fixtures"]}
    anchor_by_name = {item["name"]: item["anchor"] for item in anchor_fixture["fixtures"]}

    base, raw, anchor = resolve_case(fixture["base_case"], raw_by_name, anchor_by_name)
    failures = failure_codes(base, raw, anchor)
    if failures:
        print("CC cross-layer validator FAIL")
        print(f"FAIL base: {', '.join(failures)}")
        return 1

    failures = []
    for negative in fixture["negative_cases"]:
        case, raw, anchor = resolve_case(fixture["base_case"], raw_by_name, anchor_by_name)
        mutation = negative["mutation"]
        target = mutation.get("target")
        objects = {
            "candidate": case["candidate"],
            "support": case["support_link"],
            "binding": case["access_binding"],
            "raw": raw,
            "anchor": anchor,
        }
        if target not in MUTATION_TARGETS or objects[target] is None:
            failures.append(f"{negative['name']}:NEGATIVE_MUTATION_TARGET")
            continue
        before = copy.deepcopy(objects[target])
        apply_mutation(objects[target], mutation)
        actual_paths = changed_paths(before, objects[target])
        actual_codes = failure_codes(case, raw, anchor)
        if actual_paths != [mutation["path"]]:
            failures.append(f"{negative['name']}:NEGATIVE_MINIMAL_MUTATION")
        if actual_codes != negative["expected_failure_codes"]:
            failures.append(f"{negative['name']}:expected {negative['expected_failure_codes']}, got {actual_codes}")

    if failures:
        print("CC cross-layer validator FAIL")
        for failure in failures:
            print(f"FAIL {failure}")
        return 1
    print("CC cross-layer validator PASS")
    print("resolved registry: STD01 RawEvidence + STD02 SourceAnchor")
    print(f"negative cases rejected: {len(fixture['negative_cases'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
