# Offline cache write optimization

Measured July 23, 2026 on the same Mac mini M4 / macOS 26.5.1 host and
`hermex-synthetic-performance-v1` fixture as `BASELINE.md`: arm64 Mac Catalyst
Debug, code coverage disabled, three warm-ups, 15 reported samples, in-memory
SwiftData stores, and no server or network.

## Result

| Messages | Before cold median / p95 | After cold median / p95 | Before warm median / p95 | After warm median / p95 | Median reduction |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 50 | 10.56 / 11.33 ms | 4.85 / 5.70 ms | 11.97 / 16.60 ms | 4.91 / 5.25 ms | 54.05% cold / 59.01% warm |
| 500 | 209.87 / 216.54 ms | 44.79 / 46.60 ms | 220.56 / 235.95 ms | 44.40 / 45.33 ms | 78.66% cold / 79.87% warm |
| 5,000 | 16,285.08 / 16,986.32 ms | 448.55 / 459.74 ms | 15,143.95 / 15,562.24 ms | 443.13 / 455.66 ms | 97.25% cold / 97.07% warm |

The warm diagnostic fetch count fell from 54/504/5,004 at 50/500/5,000 rows
to two at every size: one scoped reconciliation fetch plus one global count for
the 5,000-message cap. The 5,000-row warm actor stages reported 3.02 ms encoding
and about 437 ms total persistence work in the final sample. The write executed
with `mainActor=false`; immutable snapshot capture on MainActor was 0.0014 ms
median / 0.0034 ms p95 at 5,000 rows.

Newest-50 cache reads did not regress: the 5,000-row cold/warm/cached-offline
medians moved from 1.57/1.53/1.54 ms before the change to 1.55/1.54/1.52 ms.
The smaller fixtures stayed around 1.1-1.2 ms after the change.

Raw evidence is intentionally uncommitted:

- Before: `.codex-tmp/cache-writes-off-main/pre/`
- After: `.codex-tmp/cache-writes-off-main/post/`

## Design

The app now creates one explicit SwiftData `ModelContainer` and one shared
`CacheWriter` for both Mac scenes. View models receive the writer through a
test-replaceable `CacheWriting` abstraction. UI code captures immutable,
Sendable session/message snapshots and awaits the writer; it never passes a
`ModelContext`, persistent model, view object, or closure across the boundary.

`CacheWriter` serializes requests, coalesces pending full snapshots for the same
server/session, treats semantic updates and clear/maintenance requests as
barriers, rejects stale view-model generations, and resumes every coalesced
waiter with the persisted result. Its `@ModelActor` persistence worker owns the
generated context and performs encoding, reconciliation, maintenance, and save.
Failures roll back that context and remain cache-only diagnostics in the view
models.

Reconciliation fetches the existing server/session set once, indexes it by
`cacheKey`, then updates/inserts and deletes the remaining stale rows. Nil-ID
message keys retain the existing sort-index/timestamp fallback. Nested values
are encoded once per incoming message with an actor-local encoder before model
mutation.

TTL cleanup uses predicates and SwiftData batch deletion. Cap enforcement uses
`fetchCount`, then fetches only the deterministic overflow ordered by
`cachedAt`, timestamp, `sortIndex`, and `cacheKey`. The cap is checked after
every transcript replacement. Global TTL/cap maintenance runs on the first
write, after 60 seconds, after 20 serialized writes, or when explicitly forced;
tiny writes inside a burst do not repeatedly scan global state. Clear-server
and clear-all invalidate matching generations immediately and remain ordered
barriers, so pending older snapshots cannot repopulate cleared data.

## Rejected sub-designs

- A background `Task` around the old `ModelContext` was rejected because the UI
  context and persistent models are actor-bound and cannot safely cross.
- One writer per call was retained only as a test fallback; production uses the
  shared container writer so coalescing, generations, and clear barriers span
  all views and both Mac scenes.
- Direct actor methods with no explicit queue were rejected because actor mailbox
  serialization alone cannot coalesce not-yet-started snapshots or attach older
  waiters to the newest durable result.
- Unstructured fire-and-forget UI writes were rejected because they lose error,
  cancellation, and ordering semantics.
- Unconditional maintenance after every write was rejected. Predicate batch
  cleanup plus the serialized time/write threshold preserves deterministic
  convergence without redoing global work for each optimistic mutation.
