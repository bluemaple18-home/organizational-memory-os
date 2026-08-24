# Personal Evidence and Work Record

## Goal

Solve employee knowledge capture without requiring every employee to use Codex, Claude Code, Gemini CLI, or a full AI Core memory runtime.

## Normal employee path

```text
Outlook / Teams / Jira / Web / Documents / Calendar
        |
        v
Personal Evidence Hub
        |
        v
Object Linking / Activity Timeline
        |
        v
Work Record Projection
        |
        v
Closeout (only when needed)
        |
        v
Knowledge Distillation
        |
        +--> PERSONAL
        +--> TEAM
        +--> DEPARTMENT
        +--> COMPANY
        +--> CLIENT
             Candidate
```

Power users using Codex/CC/Gemini provide richer execution evidence into the same contracts.

## Evidence sources

Priority enterprise sources:

- Outlook mail: inbox, sent mail, thread/conversation, attachments, related calendar events.
- Teams: chat, channel, replies, meetings, transcripts where policy allows.
- Jira: issue, comment, state change, close/resolution, identifiers.
- Documents/Outline: create/update/revision.
- Calendar/meeting metadata.
- Manual “this is worth remembering” capture.
- Runtime evidence from coding/agent tools.

Avoid making desktop screen recording/keylogging a default MVP requirement. Optional local activity capture can come later.

## Object-centric model

Do not force each event to belong to exactly one case. A Teams message may relate simultaneously to:

- Jira issue
- client
- order/campaign
- project
- document
- person/team

Use object-centric event concepts (OCEL-style) and project a `WorkRecord` from the graph.

Potential object link priority:

1. explicit business IDs / direct links
2. Jira/order/case/client/project identifiers
3. email/Teams thread identity
4. referenced document/URL/repository
5. participants/team
6. time proximity
7. semantic similarity

Use deterministic/heuristic matching first; embeddings/LLM second; human clarification only for low-confidence important cases.

## Work Record

`WorkRecord != Knowledge.`

It represents one coherent piece of work. Suggested fields:

- work_record_id
- tenant_id
- primary_scope
- linked_object_ids
- evidence_refs
- participants
- start/end timestamps
- problem/goal
- decisions
- actions
- result/outcome
- failed attempts
- unresolved questions
- status
- closeout_confidence
- provenance

## Closeout

AI may propose closeout but should not silently declare enterprise work complete.

Closeout signals can include:

- Jira resolution/closed
- explicit user completion
- final result/evidence present
- final customer reply
- long inactivity plus outcome signal

If required information is missing, ask the employee only the smallest number of questions needed, e.g. root cause, final fix, failed attempt, applicability/version.

## Distillation

A completed WorkRecord may produce zero or many candidates.

Possible knowledge candidates:

- Fact / product fact
- Decision rule
- Failure / anti-pattern
- Know-how / lesson

Procedure should be separate as `PROCEDURE_CANDIDATE` rather than mixed into knowledge type.

Product/industry/role/client are facets/scopes, not necessarily knowledge types.

## Prior art

### OpenChronicle — MIT
Absorb:

- event dedup/debounce
- timeline normalization
- sessionization
- reducer pattern
- idempotent rebuild
- flush/end semantics
- fallback/failure handling

Do not absorb its memory DB or memory authority as organizational truth.

### DayTrail — MIT / Apache-2.0 style donor
Absorb:

- activity-to-task link suggestion
- scoring/correlation pattern
- human accept/reject

Adapt signals to business identifiers and enterprise objects.

### OCEL 2.0
Absorb the object-centric event model so events can relate to multiple business objects.

### PM4Py — AGPL-3.0
Reference/test donor unless a licensing decision explicitly allows use. Do not casually embed in proprietary SaaS.

### Microsoft Graph
Use delta query/change notification for Outlook/Teams/Calendar incremental evidence ingestion.

### ActivityWatch — MPL-2.0
Optional local activity donor, not MVP default.

### MyContext — ELv2
Architecture/teardown reference only for hosted SaaS; do not directly embed without licensing review.
