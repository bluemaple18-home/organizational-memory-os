# Do Not Reimplement Policy

## Goal

Minimize reinvention of mature engineering without importing donor authority.

Before writing custom implementation for an important capability:

```text
Problem
 -> Existing Product Seam
 -> Prior-Art Scan
 -> Semantic / Authority Diff
 -> Reuse Failure Cases
 -> Reuse Tests
 -> Reuse Algorithms / Protocols
 -> Adapt Existing Implementation
 -> Add Dependency only if justified
 -> Custom Delta last
```

## Required card fields

Every important implementation card must contain:

- Prior Art
- Reuse Candidate
- Absorb
- Do Not Absorb
- License
- Existing Seam
- Tests / Failure Cases to Reuse
- Why Custom Code Is Still Needed

If `Why Custom Code Is Still Needed` is empty or weak, the card must not default to a custom implementation.

## Reuse modes

### DIRECT_REUSE
Use an OSS/library/protocol largely as-is behind our adapter/contract.

Examples:

- Docling parsing
- Qdrant retrieval execution
- OpenTelemetry GenAI vocabulary
- Slack Bolt event plumbing

### ADAPT
Use mature implementation but translate to our authority/contracts.

Examples:

- OpenFGA authorization mechanics -> KnowledgeAuthorizationModel
- Microsoft Graph events -> RawEvidence

### ABSORB
Port/learn algorithms, tests, failure cases or protocol patterns without adopting the subsystem.

Examples:

- Codex context compaction engineering
- OpenChronicle timeline/session logic
- Munder single-committer principle

### REFERENCE_ONLY
Use architecture/behavior as research prior art but do not embed code because licensing/product boundaries are incompatible or unclear.

Examples:

- MyContext ELv2 for hosted SaaS
- PM4Py AGPL without an explicit licensing decision

### SHOULD_NOT_ADOPT
The donor solves a different authority/runtime problem and would create a duplicate subsystem.

Examples:

- agent mailbox/wake/process manager
- blackboard DB as knowledge truth
- donor memory DB as canonical knowledge
- donor permission store as organizational permission authority

## What we are willing to custom-build

Custom code is justified where the product has unique organizational semantics:

- RawEvidence / WorkRecord / KnowledgeCandidate contracts
- organizational scope semantics
- knowledge authority and canonical identity
- review/approval semantics
- permission inheritance / managed policy floors
- conflict / supersession semantics
- ContextPolicy semantics
- verification requirements / acceptance semantics
- commercial entitlement / capability levels
- product-specific adapters connecting donors to these contracts

## License discipline

“Open source” does not mean “safe to embed in proprietary hosted SaaS”. Every dependency/adaptation card must pin and record the exact license/version.

Examples requiring caution:

- AGPL: network copyleft implications; do not casually embed.
- ELv2: hosted/managed-service limitations may apply.
- MPL-2.0: file-level copyleft obligations for modified covered files.

A permissive license still does not permit semantic authority takeover.
