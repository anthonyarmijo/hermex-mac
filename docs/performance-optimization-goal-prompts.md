# Hermex Performance Optimization Program

This document turns the current performance audit into seven independently executable Codex Goal prompts. Run them in order unless a completed goal's evidence changes the priority of later work.

The program deliberately optimizes the existing Mac Catalyst application before considering a separate native macOS UI. Most identified costs are in SwiftUI/Markdown layout, main-actor SwiftData writes, repeated growing-string work, image decoding/caching, and view-local parsing. Those costs would carry into a native SwiftUI target.

## How to use these prompts

1. Use only one active Codex Goal at a time.
2. Paste the complete prompt for that goal. Do not combine implementation goals into one large change.
3. Let the goal finish its measurements, implementation, verification, documentation, and commit before beginning the next goal.
4. Treat a failed experiment as useful evidence. Preserve the benchmark/report, remove only the experiment's own unsuccessful code, and do not force a behavioral change merely to claim a speedup.
5. Follow AGENTS.md's authorization policy: an approved goal includes branch pushes and PR creation/update. Obtain approval for merges or releases once the complete sequence is reviewable; do not ask again for steps that approval already covers.

Each goal should normally use its own issue and short branch. If no issue exists, suggested branch names are included below and follow the repository's `chore/` or `fix/` convention.

## Known baseline and constraints

- The existing long-session diagnostic uses 50 cached messages. Its hosted baseline median was 26.21 ms to the first committed frame and 22.24 ms through synchronous layout.
- After the most recent cache-first work, the corresponding medians were 25.38 ms and 22.54 ms. The difference was within scheduler/layout noise.
- Only 5 of 50 transcript rows evaluated before the first frame. The remaining first-frame cost is dominated by the visible rows' rich Markdown layout, not eager construction of all 50 rows.
- The exact `MEDIA:` marker fast path reduced 100 passes over long no-media assistant content from a 44.50 ms median to 4.58 ms, about a 90% improvement.
- Prior experiments found no reliable first-frame benefit from Markdown pre-parsing/cache, removing the scroll-metrics observer, removing the vertical-axis guard, removing paragraph `fixedSize`, or using a geometry-changing plain-text substitution. Do not repeat these experiments without new evidence or a materially different design.
- `TranscriptCacheReader` is already a non-main `@ModelActor` read boundary. Preserve it.
- The full validated baseline is 1,493 iPhone tests and 1,495 Mac Catalyst tests with zero failures. Test counts may legitimately change as coverage is added.
- The app must remain buildable for both Mac Catalyst and iPhone. Do not add third-party dependencies or invent Hermes Web UI endpoints or payloads.

## Priority and dependency map

| Order | Goal | Likely impact | Confidence | Risk | Depends on |
| --- | --- | --- | --- | --- | --- |
| 1 | Measurement harness and baselines | Enables every later decision | High | Low | None |
| 2 | Off-main, batched SwiftData writes | High responsiveness benefit during load/mutation/cache refresh | High | Medium | Goal 1 |
| 3 | Streaming and Markdown hot path | Highest likely visible smoothness benefit | Medium | High | Goal 1 |
| 4 | Bounded, downsampled image pipeline | High memory benefit; medium scrolling benefit | High | Medium | Goal 1 |
| 5 | Parse Git diffs once and off-main | Localized but highly reliable win | High | Low | Goal 1 |
| 6 | Catalyst Optimize Interface for Mac spike | Potential UI/graphics benefit; uncertain app-specific result | Medium | Medium | Goals 2–5 preferred |
| 7 | End-to-end remeasurement and architecture gate | Confirms total value and next architecture decision | High | Low | Goals 1–6 |

---

## Goal 1 — Build the repeatable performance measurement harness

Suggested branch: `chore/perf-baselines`

### Copy/paste Goal prompt

```text
Create a repeatable, evidence-producing performance baseline for Hermex before changing production behavior.

Repository and workflow requirements:
- Work in /Users/anthonyarmijo/dev/apps/personal/hermex-mac.
- Read AGENTS.md and CURRENT.md first. Read only the PROJECT_SPEC.md sections named by CURRENT.md.
- Confirm the worktree and branch before editing. Never work directly on protected master. If there is no human-selected issue and the current performance branch is no longer appropriate, create and switch to chore/perf-baselines.
- Use CodeGraph/codebase-memory tools before grep or broad file reads for code discovery.
- Preserve unrelated user changes. Do not add dependencies, change API contracts, push, open a PR, merge, tag, or run release workflows.

Objective:
Create deterministic diagnostics and a written baseline that every later performance goal can rerun on the same scenarios. This goal is instrumentation and measurement only; do not ship speculative UI, persistence, parsing, cache, or Catalyst-idiom optimizations.

Known evidence that must be preserved in the report:
- Hosted 50-message baseline: 26.21 ms median to committed frame and 22.24 ms through synchronous layout.
- Most recent result: 25.38 ms and 22.54 ms; only 5 of 50 rows evaluated.
- Rich Markdown layout is the leading known first-frame cost.
- The exact MEDIA: fast path already improved the long no-media parser benchmark by about 90%.
- Do not repeat previously rejected scroll-observer, vertical-axis-guard, paragraph-fixedSize, plain-text-substitution, or generic Markdown preparse experiments.

Required work:
1. Inventory the current diagnostics, signposts, performance tests, generated fixtures, and any xctrace workflows. Start with TranscriptPerformanceSignpost, TranscriptDisplayModelTests, ChatViewModelStreamingPaceTests, StreamingWordDrainTests, CacheStoreTests, transcript media tests, Git diff tests, and image-preview tests.
2. Define deterministic, synthetic fixtures containing no real user transcript, tokens, paths, credentials, or server data:
   - Transcript open: newest 50 messages, with representative long prose, fenced code, table, list, link, display math, reasoning/activity, and a small number of MEDIA: markers.
   - Streaming: at least short, 10,000-character, and 50,000-character assistant responses delivered in reproducible awkward SSE-sized chunks. Include Unicode grapheme clusters, CRLF, multiple spaces, open/closed code fences, tables, inline/display math, and media-like text inside and outside fences.
   - Persistence: 50, 500, and 5,000 cached messages plus a representative session list.
   - Images: repeated and unique small/large images, including transparency and orientation where supported, generated locally in tests.
   - Git diff: small, 5,000-line, and 25,000-line diffs with multiple hunks.
3. Add or refine signposts around stages rather than one opaque interval. At minimum distinguish cache fetch, cache mapping, cache write reconciliation, cache save, maintenance, streamed-token buffering, paced drain, message publication, transcript media segmentation, math segmentation, Markdown view update/layout, image load/decode/downsample/cache lookup, and Git diff parse. Keep release overhead negligible and never log transcript text, URLs containing secrets, tokens, attachment contents, or other private values.
4. Prefer deterministic counters and operation-volume assertions over flaky wall-clock CI failures. Examples include parser invocation count, bytes/characters examined, records fetched, fetch count, cache hits/misses/evictions, decoded pixel cost, and main-actor vs non-main execution. Benchmarks may report elapsed time through XCT activities, but correctness tests must not depend on a narrow timing threshold.
5. Add a documented manual Instruments procedure for a signed Mac Catalyst Debug build. Cover Time Profiler, SwiftUI, Core Animation/Hitches, Allocations, and Points of Interest. Store large traces and result bundles only under the gitignored .codex-tmp directory. The report must record Mac model/chip, OS version, build configuration, sample count, fixture identity, and whether the server/network was involved.
6. Run enough repeated samples to report median and p95 where the tooling supports it. Use the same warm-up policy and fixture for every comparison. Separate cold-cache, warm-cache, and cached-offline transcript opens.
7. Create a concise baseline report under docs/performance/ that explains how to run the diagnostics, lists present measurements, and explicitly marks metrics not yet collectable. Do not fabricate missing values.

Required scenarios and outputs:
- First cached transcript frame: cache start, cache ready, first synchronous layout, first Core Animation commit, visible row evaluations.
- Long streaming response: total main-thread CPU, paced update count, p50/p95 update cost, characters copied/scanned, frame hitches, final-content correctness.
- Cache write: total duration, main-thread duration, fetch count, objects fetched/updated/inserted/deleted, maintenance duration.
- Image stress: cache entry/cost growth, peak resident memory, decode/downsample time, hit rate after warmup.
- Git diff: parse duration and invocation count while loading, collapsing/expanding, resizing, and changing appearance.

Verification:
- Run focused Mac Catalyst tests for every diagnostic or fixture changed.
- Because diagnostics touch shared source, run an iPhone compile check or focused iPhone tests as appropriate.
- Build and launch a signed Mac Catalyst Debug app if runtime signposts or UI diagnostics changed. Do not install an unsigned signing-disabled simulator build.
- Keep full logs/results in .codex-tmp and report summaries.

Definition of done:
- Another agent can reproduce every automated benchmark from documented commands.
- The signed Mac app emits privacy-safe, stage-specific signposts for the important paths.
- The report contains real baseline values or an explicit reason a value is unavailable.
- No production behavior, UI appearance, network protocol, or cache semantics changed.
- Focused tests and the proportional cross-platform validation pass.
- Report files changed, commands run, results, remaining measurement gaps, and the next recommended goal.
- On wrap-up, update CURRENT.md and commit the verified documentation/diagnostic slice. Push the feature branch and open/update its PR unless the user requested local-only work.
```

---

## Goal 2 — Move cache writes off-main and eliminate per-record persistence work

Suggested branch: `fix/cache-writes-off-main`

### Copy/paste Goal prompt

```text
Make Hermex offline-cache writes asynchronous, actor-isolated, batched, and measurably cheaper without changing cache-first behavior or offline correctness.

Repository and workflow requirements:
- Work in /Users/anthonyarmijo/dev/apps/personal/hermex-mac.
- Read AGENTS.md and CURRENT.md first, then only the PROJECT_SPEC.md sections named in CURRENT.md. Phase 6 Offline Cache is authoritative for cache semantics.
- Confirm a clean/understood worktree. Never edit on protected master; create or switch to fix/cache-writes-off-main unless the human selected an issue branch.
- Use CodeGraph/codebase-memory discovery first. Trace every CacheStore.cacheSessions, cacheSession, cacheMessages, clearAll, and clearCache caller before changing an API.
- Preserve unrelated work. Do not add dependencies, invent API behavior, push, open a PR, merge, tag, or release.

Current problem:
- CacheStore write APIs are @MainActor and receive the UI ModelContext.
- cacheSessions/cacheMessages perform one SwiftData lookup per incoming record, then fetch stale rows, run global maintenance, JSON-encode nested fields, and save synchronously.
- Maintenance fetches all sessions/messages, filters expiry in memory, and globally sorts up to the complete message cache on every write.
- TranscriptCacheReader is already a correct non-main @ModelActor read boundary and must not regress.

Objective:
Move persistence writes and maintenance behind a dedicated SwiftData actor boundary, reconcile records in bulk, coalesce redundant snapshots safely, and ensure cache operations never create visible main-thread stalls. Preserve the exact server isolation, TTL, 5,000-message cap, ordering, stale-row deletion, mutation behavior, and offline fallback.

Required implementation sequence:
1. Re-run the Goal 1 cache-write baseline before editing. If the measurement harness is missing or inadequate, add only the minimal missing instrumentation first.
2. Map all write classes:
   - Full session-list replacement.
   - Single-session update/archive/delete.
   - Full transcript replacement after load, pagination, send, completion, edit, regenerate, fork, and reconnect.
   - Clear active-server cache, clear all cache, server removal, and logout/reset behavior.
3. Introduce a testable cache-writing abstraction and a dedicated @ModelActor writer (or the closest SwiftData-supported actor design for the deployment targets). The actor must own its ModelContext. Never pass a ModelContext, PersistentModel instance, UIKit/SwiftUI object, or non-Sendable closure across actors. Only immutable Sendable value snapshots may enter or leave the writer.
4. Construct the writer from the same ModelContainer used by the app. Inject it into SessionListViewModel and ChatViewModel in a way tests can replace with a spy/fake. Preserve the existing TranscriptCacheReading injection.
5. Bulk-reconcile instead of doing N key fetches:
   - Build incoming keys once.
   - Fetch the existing rows for the relevant server or session in one query when practical.
   - Index fetched rows by cacheKey in memory.
   - Apply updates/inserts and delete stale records from that fetched set.
   - Encode nested message values outside repeated lookup loops where safe, without sharing encoders unsafely.
   - Keep stable sortIndex and cache-key behavior, including messages with nil message IDs.
6. Optimize maintenance using predicates, sorting, limits, or supported batch APIs rather than fetching and sorting the full store in Swift. Verify every API against the repository's actual deployment targets. Do not invent unsupported SwiftData behavior.
7. Stop performing global maintenance after every tiny write. Use a documented and tested policy such as a serialized/coalesced maintenance pass after a write burst or when a cheap threshold/time condition is met. Expired data and the 5,000-message limit must still converge deterministically and must be enforced before tests/assertions that depend on them.
8. Coalesce redundant full snapshots by key when safe: the latest snapshot for a (server, session) may replace an older queued snapshot that has not started. Do not reorder distinct semantic operations. Clear/delete must act as a barrier so an older queued write cannot repopulate data after a clear. A newer server/session generation must never receive stale data from a previous selection.
9. Await actor work from UI code where durability/order is required. Main-actor callers may suspend, but they must not run persistence work synchronously. Do not use unstructured fire-and-forget tasks that silently lose ordering, errors, or cancellation semantics.
10. Preserve cache failures as non-fatal where that is current behavior. Add privacy-safe diagnostics, but do not turn an offline-cache write failure into a false network/API failure.

Tests to add or strengthen:
- Writer work executes outside MainActor and its generated ModelContext remains model-actor isolated.
- A 500-message snapshot uses bounded fetches rather than one fetch per message. Prefer an injectable counter/test seam over fragile SQL-log parsing.
- Insert, update, deletion, pagination replacement, nil-ID keys, and stable sort ordering remain correct.
- Two servers with the same session/message IDs never cross-contaminate.
- Rapid A→B→A session switching and overlapping writes end with the newest correct snapshot.
- clearCache/clearAll cannot be undone by an older queued write.
- Cancellation and writer errors do not corrupt existing cache or surface as misleading API errors.
- TTL expiry and global maxMessages eviction remain deterministic.
- Existing cache-first first-frame gating, offline fallback, optimistic messages, stream completion, edits, regeneration, and fork behavior remain correct.

Performance acceptance criteria:
- The cache-write signpost shows persistence reconciliation, encoding, maintenance, and save outside MainActor.
- The incoming-record path no longer performs one SwiftData fetch per record.
- For the deterministic 500- and 5,000-message fixtures, main-thread cache-write work is reduced to snapshot capture/publication and is not a visible stall.
- Report before/after median and p95 total duration, main-thread duration, fetch count, and maintenance duration. A wall-clock regression greater than 10% must be explained and justified by a larger responsiveness win; otherwise continue optimizing or reject the design.
- Cache reads and first cached frame must not regress beyond normal measurement noise.

Verification:
- Run focused CacheStore, cache-first transcript, SessionList mutation, ChatViewModel send/edit/regenerate/fork/reconnect, cancellation, and offline tests on Mac Catalyst.
- Run focused iPhone tests because the persistence source is shared.
- Before committing, run the full Mac Catalyst XCTest suite. Run an iPhone compile check or the focused/full iPhone suite proportionally to the actual blast radius and do not repeat an unchanged green suite unnecessarily.
- Build and launch the signed Mac app. Manually verify cold and warm cached opening, rapid session switching, load older, send without content loss, server switching, and clear-cache behavior. Do not change the developer's network or server state without permission.

Definition of done:
- Cache writes no longer execute persistence work on MainActor.
- N-per-record fetches and unconditional full-store maintenance are removed.
- Ordering, durability, isolation, TTL, cap, stale deletion, and offline behavior have explicit passing tests.
- Before/after measurements and any rejected sub-designs are recorded under docs/performance/.
- All proportional validation is green and the signed Mac app launches.
- Report files changed, commands, results, manual checks, remaining risks, and next step.
- On wrap-up, update CURRENT.md and commit the verified slice. Push the feature branch and open/update its PR unless the user requested local-only work.
```

---

## Goal 3 — Reduce growing-string and Markdown work during streaming

Suggested branch: `fix/streaming-render-performance`

### Copy/paste Goal prompt

```text
Improve the smoothness and CPU efficiency of long streamed Hermes responses while preserving byte-identical content, Markdown behavior, word-paced reveal, recovery deduplication, and scroll behavior.

Repository and workflow requirements:
- Work in /Users/anthonyarmijo/dev/apps/personal/hermex-mac.
- Read AGENTS.md and CURRENT.md first; read only CURRENT.md's named PROJECT_SPEC.md sections.
- Confirm the worktree and create/switch to fix/streaming-render-performance unless a human-selected issue branch applies. Never work on protected master.
- Use CodeGraph/codebase-memory to trace SSE event → ChatStreamCoordinator → ChatViewModel buffering/drain → transcript display model → MessageBubbleView → TranscriptMediaParser/MarkdownMathSegmenter → MarkdownUI before editing.
- No new dependencies, invented SSE/API behavior, unrelated UI redesign, push, PR, merge, tag, or release.

Current problem and existing behavior:
- Normal tokens are appended to pendingAssistantTokenChunks, repeatedly joined for effective content, backlog unit counting, and draining.
- appendAssistantToken constructs flushedContent + pendingAssistantTokenChunks.joined() before deduplicatedReplayToken can immediately discover that the connection is not a replay.
- drainStreamingContentTick joins the backlog for unitCount, and flushAssistantTokens joins it again before splitting.
- Publishing a paced chunk replaces the whole ChatMessage value and causes the active assistant row to re-run transcript media detection, math segmentation/inline-math replacement, Markdown parsing, SwiftUI layout, and bottom-follow work.
- TranscriptMediaParser already has an exact MEDIA: marker fast path; do not undo it or repeat the rejected generic Markdown preparse experiments.
- StreamingWordDrain behavior and ChatViewModelStreamingPaceTests define important product semantics: gradual reveal, adaptive backlog catch-up, completion flush, Unicode safety, and byte-identical convergence.

Objective:
Make per-token/per-flush work scale with the new chunk or mutable tail wherever possible, then use Time Profiler/SwiftUI evidence to reduce repeated Markdown work without breaking Markdown semantics. The result must feel at least as smooth as the current paced stream and must never alter final content.

Required implementation sequence:
1. Rerun the Goal 1 streaming fixture and record before values for short, 10,000-character, and 50,000-character responses. Capture total main-thread CPU, p50/p95 paced-update duration, update count, characters copied/scanned, frame hitches, peak memory, time from final SSE event to final visible content, and final byte equality.
2. Add stage-specific signposts/counters if needed so token buffering, replay dedup, backlog accounting, drain/split, ChatMessage publication, media scan, math scan, Markdown body update/layout, animation, and scroll follow can be distinguished. Do not log content.
3. Apply the highest-confidence buffer fixes first:
   - On a normal non-replay connection, do not construct the full effective content solely for replay deduplication.
   - Replace repeated [String].joined() work with a tested buffer representation that supports append, backlog unit accounting, bounded head drain, full flush, reset, and replay visibility without repeatedly copying the complete accumulated response.
   - Track drainable unit metadata incrementally where possible while preserving Character/grapheme boundaries, whitespace semantics, CRLF, combining marks, and exact head + tail reconstruction.
   - Avoid scanning messages linearly for the streaming message on every tick if profiling proves it material; any retained index/identity must stay valid across load, merge, recovery, edit, pagination, and ID replacement.
4. Rerun the streaming benchmark after the buffer-only slice. Keep it only if correctness is green and copied/scanned volume and CPU improve. Record the independent result before attempting renderer changes.
5. Profile the renderer with representative content. Identify the actual expensive MarkdownUI/SwiftUI stacks and quantify TranscriptMediaParser, MarkdownMathSegmenter/MarkdownMathProtection, inline-math replacement, Markdown(content), custom code/table/math blocks, text fade rendering, layout, animation, and scroll follow.
6. Implement only evidence-supported renderer changes. Candidate directions, in preferred safety order, are:
   - Fast-path math scanning when no supported delimiter is present, analogous to the media marker fast path.
   - Retain immutable parsed/segmented results for settled non-streaming rows using a bounded cache keyed by content plus all rendering inputs; prove invalidation and memory bounds. Do not repeat an unbounded or non-impactful preparse cache.
   - Isolate a semantically safe settled prefix from the mutable streaming tail so completed blocks do not reparse/re-layout. This is allowed only if tests prove equivalence for paragraphs, lists, block quotes, fenced code, tables, links, inline/display math, and constructs whose meaning can cross a proposed boundary. An open or ambiguous Markdown construct must stay in the mutable tail.
   - Adapt render publication batching to frame budget for very large backlogs only if word-paced appearance and maximum reveal lag remain acceptable. Do not silently replace Markdown with plain text or remove the existing reveal behavior.
7. Reject and document any candidate that changes paragraph geometry, causes scroll jumps, breaks text selection/link interaction, increases memory without a bound, or merely shifts work while p95 frame/update cost stays unchanged.
8. Keep completed non-streaming rendering byte/visually equivalent. Fallback rendering must remain controlled by MarkdownContentRenderingPolicy, not by response length alone unless a separate product decision is explicitly approved.

Correctness and regression tests:
- Existing streaming pace, motion, word drain, reconnect/replay, snapshot, completion, cancellation, error, interim-assistant, reasoning, and tool-call tests remain green.
- Final streamed content is byte-identical across awkward chunks containing ZWJ emoji, flags, combining marks, CRLF, tabs, leading/trailing/multiple spaces, and empty chunks.
- Replay dedup handles exact prefix, partial overlap, reconnect, and tokens arriving after the replay boundary without duplication or loss.
- Markdown cases include open/closing fences split across chunks, nested lists, block quotes, tables whose rows arrive later, links split across chunks, inline/display math delimiters split across chunks, and MEDIA: markers inside/outside fences.
- Scroll-away is never pulled back; bottom-follow remains smooth; Scroll to latest still works; loading older messages preserves its anchor.
- Reduce Motion disables streaming motion as it does today.
- Text selection, code blocks, tables, math, links, media preview, timestamps, reasoning/activity, and tool cards still work when streaming ends.

Performance acceptance criteria:
- Normal non-replay token append no longer constructs or scans the full effective response.
- Buffer bookkeeping does not repeatedly join the entire pending chunk array for each append/tick.
- Total copied/scanned characters for a deterministic long stream grows near-linearly rather than quadratically in response length for the app-owned buffering/scanning stages.
- Report before/after median and p95 update cost, main-thread CPU, total stream CPU, frame hitches, peak memory, and completion latency for all fixture sizes.
- The 50,000-character fixture must show a meaningful measured improvement in at least one user-relevant metric with no material regression in the others. If Markdown layout remains dominant, report the precise stack and the next bounded experiment instead of claiming success.

Verification:
- Run focused Mac Catalyst streaming, Markdown, transcript media, math, scrolling, cache/reconnect, and performance tests throughout.
- Run focused iPhone tests or a compile check for shared-source changes.
- Before committing, run the full Mac Catalyst XCTest suite.
- Build and launch the signed Mac app. Manually stream representative prose, code, list/table, math, link, reasoning/tool, and media content; test scroll-away/return and rapid session switching.
- Keep traces and full logs in .codex-tmp.

Definition of done:
- The app-owned streaming buffer path avoids avoidable full-response copying/scanning.
- At least one evidence-supported rendering optimization is implemented, or profiling conclusively documents why no safe renderer change should ship in this slice.
- Content, Markdown, recovery, scroll, motion, and completion correctness are covered and green.
- Before/after evidence and rejected experiments are recorded under docs/performance/.
- The signed Mac app launches and proportional cross-platform validation passes.
- Report files, commands, results, manual checks, remaining hotspots, and next step.
- On wrap-up, update CURRENT.md and commit the verified slice. Push the feature branch and open/update its PR unless the user requested local-only work.
```

---

## Goal 4 — Bound and downsample transcript image caches

Suggested branch: `fix/bounded-image-cache`

### Copy/paste Goal prompt

```text
Make Hermex transcript image loading memory-bounded, correctly namespaced, downsampled before full decode, and smooth under image-heavy scrolling.

Repository and workflow requirements:
- Work in /Users/anthonyarmijo/dev/apps/personal/hermex-mac.
- Read AGENTS.md and CURRENT.md first; read only the spec sections named by CURRENT.md.
- Confirm the worktree and use fix/bounded-image-cache unless a human-selected issue branch applies. Never work directly on protected master.
- Use CodeGraph/codebase-memory to inventory every transcript/attachment/link-preview/file-preview image load, cache, downsampler, in-flight task, namespace, and cleanup path before editing.
- Do not add dependencies, change server endpoints/payloads, expose server/auth values in logs, push, open a PR, merge, tag, or release.

Current problem:
- AttachmentImageCache and TranscriptMediaImageCache are actors with unbounded [Key: UIImage] dictionaries.
- AttachmentImageCache downsamples through ImagePreviewDownsampler, but TranscriptMediaImageCache currently constructs UIImage directly from the complete payload.
- The attachment cache key is only the attachment path; identical paths from different configured servers could collide unless the surrounding lifecycle already guarantees uniqueness.
- In-flight requests are deduplicated but cache size, decoded byte cost, namespace invalidation, and memory-pressure behavior are not explicit.
- TranscriptLinkPreviewCache has an entry-count limit but also retains image Data; include it in the byte-cost audit rather than assuming count alone is sufficient.

Objective:
Introduce deterministic count and decoded-memory limits, correct server/session namespacing, pre-decode downsampling, cancellation-safe in-flight deduplication, and explicit invalidation. Preserve image fidelity, orientation, transparency where applicable, preview/export behavior, authenticated loading, and iPhone compatibility.

Required implementation sequence:
1. Rerun the Goal 1 image fixture. Measure cold decode/downsample time, warm-hit latency, cache hit/miss/eviction counts, decoded pixel cost, peak resident memory, and scrolling hitches for repeated and unique images.
2. Complete the cache inventory. At minimum inspect AttachmentImageCache, TranscriptMediaImageCache, TranscriptLinkPreviewCache, ImagePreviewDownsampler, composer/pending thumbnails, file previews, media previews/exports, and DisplayMathView's NSCache. Distinguish view-local state from process-wide caches.
3. Define one small, testable cache policy rather than scattered magic numbers:
   - Maximum entry count and maximum decoded byte cost.
   - Cost estimated from decoded dimensions/bytes per row rather than compressed Data size.
   - LRU or similarly deterministic recency eviction.
   - Defaults justified by measured Mac/iPhone behavior, with injectable small limits for unit tests.
   - No access tokens, cookies, private headers, or raw secret URLs in cache keys or diagnostics.
4. Either reuse a repository cache pattern such as TranscriptLinkPreviewCache or extract a minimal internal bounded cache. Do not introduce a third-party caching library. Actor isolation and Sendable boundaries must remain correct.
5. Make image keys include the stable, privacy-safe server/account/cache namespace plus the media/attachment identity. Reuse an existing namespace when it is correct. Verify server switching, account switching, logout, server removal, and same-path-on-two-servers behavior.
6. Downsample before full-resolution UIKit decode with ImageIO. Choose target pixel dimensions from actual rendered size and screen scale or a documented capped tier. Avoid decode → render → resize pipelines that temporarily materialize the full image. Preserve orientation. Test alpha-bearing images and do not blindly JPEG-reencode formats where transparency or animation matters.
7. Deduplicate concurrent loads by final cache key. Ensure in-flight entries are removed with defer-equivalent cleanup on success, failure, and cancellation. Decide and test whether one cancelled waiter cancels shared work or merely stops awaiting it.
8. Add explicit cache APIs for remove(namespace:), removeAll(), metrics snapshot, and memory-pressure/background handling where supported. Clearing one server must not evict another unless global memory pressure requires it. Logout/reset must not leave authenticated content reachable through a new account context.
9. Keep export/fullscreen behavior correct. Thumbnails may be bounded/downsampled, but an explicit full-resolution preview/export path must still request or retain the appropriate source without pinning every full-resolution image globally.
10. Audit TranscriptLinkPreviewCache image Data cost and bound it by bytes as well as entries if measurements show the current 96-entry cap can retain too much data.

Tests to add or strengthen:
- Deterministic LRU order, count limit, byte-cost limit, recency refresh on hit, replacement cost, and remove namespace/all.
- Two configured servers using the same path/reference return their own images.
- Concurrent identical requests perform one load; different namespaces do not deduplicate incorrectly.
- Failure and cancellation remove in-flight state and permit retry.
- Large input is downsampled to the promised maximum before display decode.
- Orientation and alpha survive where the source format supports them; malformed/non-image payloads fail safely.
- Full-resolution preview/export behavior remains available.
- Link-preview image storage respects its byte policy if changed.
- Repeated long scrolling cannot grow the shared cache beyond its configured count/cost.

Performance acceptance criteria:
- Shared image caches have deterministic, tested bounds.
- Transcript media no longer requires a full-resolution UIImage decode merely to show an inline preview.
- The image stress fixture reaches a stable cache cost instead of growing with every unique image.
- Report cold and warm p50/p95 load latency, peak resident memory, decoded cost, hit rate, eviction count, and scroll hitches before/after.
- Warm-hit performance must not materially regress. Any fidelity tradeoff must be visible, documented, and approved rather than hidden.

Verification:
- Run focused Mac Catalyst attachment, transcript media, link preview, preview/export, cancellation, server-isolation, and new cache-policy tests.
- Run focused iPhone tests because UIKit/ImageIO code is shared.
- Before committing, run the full Mac Catalyst XCTest suite.
- Build and launch the signed Mac app. Manually test image-heavy transcript scrolling, repeated reopen, server/session switching, inline media, attachment grid, link previews, fullscreen preview, and export.
- Keep traces/results in .codex-tmp.

Definition of done:
- Process-wide transcript image caches are bounded by count and decoded cost.
- Inline images are downsampled safely before large display decode.
- Namespace isolation, cancellation, retry, invalidation, preview, and export semantics have passing tests.
- Before/after memory and smoothness results are recorded under docs/performance/.
- Proportional validation is green and the signed Mac app launches.
- Report files, commands, results, manual checks, remaining risks, and next step.
- On wrap-up, update CURRENT.md and commit the verified slice. Push the feature branch and open/update its PR unless the user requested local-only work.
```

---

## Goal 5 — Parse each Git diff once, outside SwiftUI body evaluation

Suggested branch: `fix/git-diff-parse-once`

### Copy/paste Goal prompt

```text
Remove repeated Git diff parsing from SwiftUI body evaluation and keep large-diff interaction responsive.

Repository and workflow requirements:
- Work in /Users/anthonyarmijo/dev/apps/personal/hermex-mac.
- Read AGENTS.md and CURRENT.md first; read only CURRENT.md's named spec sections.
- Confirm the worktree and use fix/git-diff-parse-once unless a human-selected issue branch applies. Never work on protected master.
- Use CodeGraph/codebase-memory to trace GitDiffView, GitDiff API loading, DiffHunk.parse, all presentation sites, and parser tests before editing.
- Do not add dependencies, change Git API shapes, push, open a PR, merge, tag, or release.

Current problem:
- GitDiffView.diffBody executes `let hunks = DiffHunk.parse(diff.diff ?? "")` during SwiftUI body evaluation.
- Changes to collapsedHunks, window geometry, appearance, or other view state can reevaluate the body and reparse the same raw diff.
- Parsing splits the complete string, finds headers, allocates lines/hunks, calculates line numbers, and later filters lines for addition/deletion counts.

Objective:
Parse a successful textual diff once per loaded response, perform expensive pure parsing off MainActor where safe, publish one immutable loaded view model, and reuse it through collapse/expand, resize, appearance, and presentation updates.

Required implementation sequence:
1. Run the Goal 1 small/5,000/25,000-line diff diagnostics. Record parse duration, main-thread duration, invocation count on initial load, and invocation count after repeated collapse/expand and resize/appearance invalidations.
2. Introduce an immutable value such as LoadedGitDiff/ParsedGitDiff that contains the original GitDiff metadata, parsed hunks, and precomputed fallback addition/deletion totals. Use naming that fits the codebase.
3. In load(), handle binary and tooLarge responses without parsing. For a normal textual diff, parse exactly once after the API response and before publishing loaded state.
4. Move the pure parse off MainActor when the deployment/concurrency model supports it. Pass only Sendable values. DiffHunk, DiffLine, and Kind store only value data and may receive explicit Sendable conformance after auditing them. Do not capture a SwiftUI view, API client, ModelContext, or mutable state in Task.detached.
5. Publish the parsed result on MainActor only if the load generation is still current and the task was not cancelled. Retry must replace the previous result cleanly; dismissing the view must not publish late work.
6. Render only the stored hunks. Collapse/expand, Collapse All, geometry changes, and appearance changes must perform zero additional parses for unchanged raw content.
7. Preserve binary/too-large/empty/error/retry states, synthetic no-header patches, hunk IDs, old/new line numbering, line colors, text selection, horizontal/vertical scrolling, and accessibility.
8. Keep DiffHunk.parse pure and directly testable unless a demonstrably better parser organization is needed. Do not add a global unbounded raw-diff cache; view-lifetime storage is sufficient for the known problem.

Tests to add or strengthen:
- Existing standard hunk, synthetic patch, headerless, line-number, and empty parser tests remain green.
- Loaded normal diff parses once; state changes/collapse toggles do not reparse.
- A retry with new content replaces hunks and performs one new parse.
- Binary and tooLarge responses do not parse raw text.
- Cancellation/dismissal cannot publish stale parsed state.
- Fallback addition/deletion totals match the previous reduce/filter behavior.
- A 25,000-line fixture parses without blocking MainActor and preserves exact hunk/line output.

Performance acceptance criteria:
- Initial parsing occurs once per textual API response.
- Collapse/expand, resize, and appearance changes cause zero additional parses.
- MainActor contains only final state publication, not the large string split/hunk construction.
- Report before/after parse count, total parse duration, main-thread duration, and interaction latency for all fixture sizes.

Verification:
- Run focused GitWorkspaceViewModel/GitDiff parser and new load-state tests on Mac Catalyst.
- Run focused iPhone tests or compile validation because the view is shared.
- Build and launch the signed Mac app because this changes UI loading/state behavior.
- Manually open small and large diffs, collapse/expand individual/all hunks, resize, switch appearance if practical, dismiss during load, and retry an induced test failure without changing production server state.
- Before committing, run the full Mac Catalyst XCTest suite.

Definition of done:
- No DiffHunk.parse call remains in a SwiftUI body/computed rendering path.
- Each loaded textual diff is parsed once and safely reused.
- Large parse work is off-main, cancellation-safe, and covered by tests.
- Before/after evidence is recorded under docs/performance/.
- Validation is green and the signed app launches.
- Report files, commands, results, manual checks, risks, and next step.
- On wrap-up, update CURRENT.md and commit the verified slice. Push the feature branch and open/update its PR unless the user requested local-only work.
```

---

## Goal 6 — Verify and benchmark “Optimize Interface for Mac”

Suggested branch: `chore/mac-idiom-spike`

### Copy/paste Goal prompt

```text
Determine, through a reversible A/B spike, whether Mac Catalyst's “Optimize Interface for Mac”/Mac user-interface idiom improves Hermex's visual quality, performance, or energy use enough to adopt.

Repository and workflow requirements:
- Work in /Users/anthonyarmijo/dev/apps/personal/hermex-mac.
- Read AGENTS.md and CURRENT.md first; read only CURRENT.md's named PROJECT_SPEC.md sections.
- Confirm the worktree and use chore/mac-idiom-spike unless a human-selected issue branch applies. Never work on protected master.
- Use CodeGraph/codebase-memory to inventory targetEnvironment(macCatalyst), UIKit representables, Mac-specific scale/layout/window code, trait/idiom checks, tests, and target settings before editing.
- Because Apple/Xcode behavior can change, verify the exact setting and compatibility rules against current official Apple documentation. Use only official Apple sources for the technical decision.
- Do not add dependencies, begin an AppKit/native rewrite, broadly redesign the UI, push, open a PR, merge, tag, or release.

Known uncertainty:
- The project supports Mac Catalyst and has Mac-specific layout/window code, but current command-line build settings did not conclusively prove whether the app is using the pad idiom (“Scale Interface to Match iPad”) or Mac idiom (“Optimize Interface for Mac”).
- Apple documents that Mac idiom can provide AppKit-like controls, sharper text/no interface scaling, and some graphical performance benefits, but it can also change metrics/layout and make some UIKit behavior unavailable.

Objective:
First prove the current runtime idiom. Then produce two otherwise identical signed Mac Catalyst builds, compare them using the same deterministic fixtures and manual UI matrix, and make an evidence-based adopt/reject/follow-up recommendation. This goal is a spike; do not bury broad remediation inside the experiment.

Required implementation sequence:
1. Determine the current state through multiple sources:
   - Xcode project/target configuration and `xcodebuild -showBuildSettings`.
   - The built app's processed Info.plist/metadata.
   - A privacy-safe DEBUG/runtime diagnostic of the actual userInterfaceIdiom and relevant trait values.
   - Current official Apple documentation describing the supported selection mechanism.
   Record the evidence and do not infer the mode from SUPPORTS_MACCATALYST alone.
2. Establish the standard-mode baseline with the Goal 1 fixtures after Goals 2–5 if available. Use a signed build and record first-frame, streaming p50/p95, scroll hitches, CPU, peak memory, energy impact, and representative screenshots at fixed window sizes.
3. Create the smallest reversible A/B configuration that selects the alternate supported idiom. Avoid intermixing layout fixes so the first comparison isolates the platform mode. Document every target/build/Info.plist change.
4. Build and launch the signed alternate app. Verify that the runtime diagnostic proves the intended idiom. If the setting is unavailable or incompatible with deployment targets, stop and document that rather than emulating it with custom scaling.
5. Run the exact same automated fixtures, sample counts, warm-up policy, window sizes, and Instruments templates. Record medians/p95 and visual screenshots.
6. Execute a Mac UI compatibility matrix:
   - Main/session/settings window sizing, minimum sizes, restoration, multiple scenes, toolbar, sidebar, sheets/popovers, menus, commands, focus, and keyboard shortcuts.
   - Transcript Markdown, code, tables, math, links, text selection, media/attachments, scrolling, bottom-follow, and Scroll to latest.
   - Composer NSText/UI wrapper behavior, multiline sizing, selection, paste/drop, slash completion, dictation/voice controls if available, and focus restoration.
   - Git workspace/diffs, kanban/tasks, settings forms, onboarding/login, file/image preview/export, share/deep links, alerts, haptics guards, accessibility, Reduce Motion, light/dark mode, and interface scale preferences.
   - Retina and external-display scale changes if the available hardware permits.
7. Categorize every difference as improvement, acceptable adaptation, regression, or blocker. Do not “fix forward” more than a few trivial compatibility issues in the spike. If adoption needs broad source changes, estimate and split them into a separate implementation goal.
8. Compare against the iPhone target. The alternate Mac setting and any compile guards must not alter iPhone runtime behavior or break its build.

Decision criteria:
- Recommend adoption only if the alternate idiom is proven at runtime, has no critical functional/accessibility blocker, materially improves Mac visual fidelity or at least one measured performance/energy metric, and does not materially regress the other key metrics.
- Recommend rejection if benefits are negligible, layout/input regressions are significant, or the remediation cost exceeds the measured value.
- Recommend a follow-up adoption goal if the mode is clearly beneficial but requires a bounded, estimable compatibility pass.
- Do not recommend a native AppKit rewrite solely because this Catalyst mode is neutral or problematic; that is a separate architecture decision.

Verification:
- Run focused Mac Catalyst tests for any setting/trait/conditional code touched.
- Run an iPhone compile check or focused tests to prove isolation.
- Build and launch both signed Mac variants. Never use CODE_SIGNING_ALLOWED=NO for manual installation/testing.
- Keep full traces and screenshots in .codex-tmp unless a small comparison image is intentionally added to docs.

Definition of done:
- Current and alternate idioms are proven rather than assumed.
- A controlled, reproducible A/B comparison covers performance, energy, visual quality, interaction, accessibility, and iPhone isolation.
- docs/performance/ contains the setting evidence, Apple source links, measurements, UI matrix, regressions, remediation estimate, and adopt/reject/follow-up recommendation.
- Any unsuccessful experimental project changes are removed without disturbing unrelated work; successful trivial diagnostic/documentation changes are verified.
- Report files, commands, results, manual checks, recommendation, and next step.
- On wrap-up, update CURRENT.md and commit the verified spike/report. Push the feature branch and open/update its PR unless the user requested local-only work.
```

---

## Goal 7 — Re-measure the complete app and decide the next architecture step

Suggested branch: `chore/performance-validation`

### Copy/paste Goal prompt

```text
Perform the final integrated Hermex performance validation, quantify the cumulative gains from completed optimization goals, find regressions, and make the evidence-based Catalyst-versus-native next-step recommendation.

Repository and workflow requirements:
- Work in /Users/anthonyarmijo/dev/apps/personal/hermex-mac.
- Read AGENTS.md and CURRENT.md first; read only the spec sections named in CURRENT.md.
- Confirm that the intended completed performance slices are present. Do not silently merge/cherry-pick branches or overwrite user changes. If integration work is required, stop and get human approval for the exact branch/commit plan.
- Use chore/performance-validation unless a human-selected issue branch applies. Never work directly on protected master.
- Use CodeGraph/codebase-memory for final blast-radius review.
- Do not add dependencies or introduce new feature work outside this goal. Branch pushes and PR updates are covered by the selected task; merges, tags, release dispatch, and publication require explicit approval for the described sequence.

Objective:
Run the same baseline suite and real-app manual scenarios after the cache-write, streaming/Markdown, image-cache, Git-diff, and Catalyst-idiom decisions. Produce one decision document with measured cumulative results, remaining hotspots, regressions, and a recommendation for the next performance investment. This goal fixes only regressions caused by the completed performance slices; it does not start another speculative optimization.

Required work:
1. Inventory exactly which goals/commits are included and list any that were rejected or deferred. Confirm repository cleanliness and expected branch history.
2. Re-run the deterministic Goal 1 suite with the same hardware, OS, build configuration, fixtures, sample counts, warm-up rules, window sizes, and Instruments templates. If environment details changed, state that comparisons are not strictly controlled and rerun the old baseline on the same current environment when possible.
3. Report before/after median and p95 for:
   - First cached transcript frame, synchronous layout, cache readiness, and visible rows.
   - Long streaming update cost, total CPU, copied/scanned volume, frame hitches, completion latency, and peak memory.
   - Cache write total/main-thread duration, fetch count, maintenance duration, correctness under rapid operations.
   - Image cold/warm latency, decoded/cache cost, peak memory, hit rate, eviction, and scroll hitches.
   - Git diff parse count/duration/main-thread time and collapse/resize interaction.
   - Mac idiom A/B results if that goal completed.
4. Run the full arm64 Mac Catalyst XCTest suite with code coverage disabled if that remains the stable repository practice. Run proportional iPhone validation, escalating to the full iPhone suite if shared infrastructure or target settings changed across the integrated work.
5. Produce and launch a signed Mac Catalyst Debug build. If practical, also measure an optimized/Release build without weakening signing or entitlements. Never manually test an unsigned simulator build.
6. Perform an authenticated manual regression matrix without creating/sending unwanted content:
   - Cold/warm cached open on representative short and long sessions.
   - Composer responsiveness, draft preservation, send only if the developer has approved a test message, streaming, cancel/reconnect, reasoning/activity/tool cards, and completion.
   - Scroll away, bottom-follow, Scroll to latest, older-page anchor preservation, rapid session switching, and offline fallback only if the developer intentionally makes the server unreachable.
   - Image-heavy rows, link previews, media preview/export, large Git diff collapse/expand, settings/onboarding/window behavior, light/dark mode, Reduce Motion, and accessibility basics.
7. Inspect Time Profiler, SwiftUI, Core Animation/Hitches, Allocations, and Points of Interest traces. Name the remaining top stacks with measured shares; do not use generic labels such as “SwiftUI is slow” when a specific MarkdownUI/text/layout function is visible.
8. Check for regressions in correctness, memory leaks, actor/data races, cancellation, stale publication, server isolation, energy, and launch size/time. Fix only regressions attributable to the performance changes and re-run the affected validation.
9. Write a final docs/performance/ report with:
   - Executive summary and cumulative wins.
   - Controlled before/after table and limitations.
   - Shipped, rejected, and deferred experiments with reasons.
   - Remaining hotspots ranked by measured user impact, confidence, implementation cost, and risk.
   - Recommended monitoring/signposts to retain.
   - A clear architecture decision.

Architecture decision gate:
- Recommend staying with Catalyst if performance targets are acceptable or remaining hotspots are still framework-independent app work.
- Recommend a small native macOS prototype only if a specific required Mac UX/API is blocked by Catalyst or profiling shows the current transcript/composer architecture cannot meet the target after the completed optimizations.
- If a native prototype is warranted, propose—not implement—a separate target sharing models, networking, API/SSE decoding, persistence value types, and view models. Prototype only transcript + composer with the same fixtures.
- Require an A/B benchmark before any full rewrite. Define the success threshold in advance; a useful default is a sustained, reproducible improvement of at least 20–30% in the blocked metric or access to a required native capability, with no unacceptable correctness/maintenance cost.
- Distinguish native SwiftUI from a custom AppKit text/scrolling implementation. Native SwiftUI alone may preserve the same Markdown/SwiftUI layout cost; do not treat target migration as a guaranteed speedup.

Definition of done:
- All intended performance slices are validated together with controlled before/after evidence.
- Full Mac tests, proportional iPhone validation, signed Mac build/launch, and the manual matrix are complete or any externally blocked item is explicitly documented.
- Regressions introduced by the performance work are fixed and reverified.
- The final report ranks remaining work and makes a concrete Catalyst/native-prototype recommendation based on measurements.
- Report files changed, exact commands, test counts/results, manual checks, measurement limitations, remaining risks, and recommended next action.
- On wrap-up, update CURRENT.md and commit the verified validation/report slice. Push the feature branch and open/update its PR unless the user requested local-only work.
```

## Expected program outcome

After Goal 7, Hermex should have:

- Reproducible performance measurements instead of subjective impressions.
- Cache writes that suspend the UI rather than execute persistence work on it.
- Streaming work that avoids avoidable full-response copying and has a measured Markdown strategy.
- Bounded image memory with correct server isolation and lower decode cost.
- Git diff parsing that happens once per response, not once per view update.
- A controlled answer on whether the Catalyst Mac idiom is beneficial.
- A defensible architecture decision with a pre-agreed benchmark gate before any native macOS rewrite.
