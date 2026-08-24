# Context Budget and Retrieval

## Why this is an architecture primitive

Context Budget directly affects:

- token cost
- latency
- retrieval precision
- hallucination risk
- context pollution
- scalability

Do not load all available company/personal/team/graph/history context for every query.

## Required flow

```text
Query
 -> Identity / Permission
 -> Intent / Domain Classification
 -> Candidate Knowledge Sources
 -> Authority / Priority / Freshness
 -> Context Budget
 -> Bounded Retrieval
 -> LLM
```

## ContextPolicy

Knowledge SaaS owns the policy semantics. Suggested fields:

- source
- scope
- authority
- priority
- freshness
- estimated_tokens
- permission
- load_policy
- optional reserve class
- optional source quota

The donor implementation may count/compact tokens, but it does not decide organizational authority.

## Engineering prior art to absorb

### OpenAI Codex / coding-agent context engineering

Absorb:

- token estimation
- reserve tokens
- keep-recent windows
- turn boundary preservation
- tool-call pair preservation
- compaction/summarization triggers
- large context cutoff
- tool-output limiting
- failure handling around compaction

Do not absorb:

- rollout/session identity as knowledge identity
- Codex state DB as canonical knowledge store
- runtime lifecycle as Knowledge SaaS lifecycle

### Microsoft GraphRAG — MIT

Absorb/adapt:

- token-aware context assembly
- mixed source context construction
- local/global search context patterns
- entity/relationship/text-unit context assembly

Do not adopt GraphRAG as canonical knowledge authority.

### Qdrant — Apache-2.0

Use as retrieval execution donor:

- dense/sparse/hybrid search
- payload filters
- tenant filtering/shards
- metadata routing

Do not let vector indexes become canonical truth.

## Bounded retrieval

Bounded retrieval should be constrained by both authorization and budget. Typical sequence:

1. build authorized retrieval space
2. classify intent/domain
3. select source classes
4. rank by authority/freshness/priority
5. allocate token/source budgets
6. retrieve within those bounds
7. optionally rerank
8. construct final context

## Telemetry projection

Measure at least:

- retrieval latency
- filtered candidates
- retrieved candidates
- source mix
- estimated/retrieved tokens
- model/provider
- input/output tokens
- total latency
- cost estimate
- citation count/hit
- failure

Prefer OpenTelemetry GenAI semantic conventions for projection. OTel is not application/knowledge truth.
