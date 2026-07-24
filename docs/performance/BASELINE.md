# Hermex performance baseline

This is the measurement contract for performance work after Mac v1.1. It adds
diagnostics and synthetic workloads only; it does not change UI, persistence,
parsing, caching, or network behavior. The fixture identity is
`hermex-synthetic-performance-v1`.

## Rules for comparisons

- Use a signed arm64 Mac Catalyst Debug build, `-enableCodeCoverage NO`, three
  unreported warm-ups, then 15 reported samples.
- Compare the same fixture identity, machine, OS, build configuration, and
  sample count. Report median and p95. Do not turn elapsed time into a narrow CI
  pass/fail threshold.
- Keep `.trace`, `.xcresult`, DerivedData, and full logs under
  `.codex-tmp/perf-baseline/`; never commit them.
- Record cache state as cold, warm, or cached-offline and say whether a server or
  network was involved. Automated fixtures never use either.
- Signposts contain only stage names and integer operation volumes. They never
  emit transcript text, session IDs, URLs, paths, tokens, attachment bytes, or
  credentials.

## Automated run

From the repository root:

```sh
mkdir -p .codex-tmp/perf-baseline/logs .codex-tmp/perf-baseline/results
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project HermesMobile.xcodeproj \
  -scheme HermesPerformanceBaselines \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath .codex-tmp/perf-baseline/DerivedData \
  -resultBundlePath .codex-tmp/perf-baseline/results/baselines.xcresult \
  -enableCodeCoverage NO \
  -only-testing:HermesMobileTests/PerformanceBaselineFixtureTests \
  -only-testing:HermesMobileTests/TranscriptMessageTests/testCacheFirstTranscriptFrameCommitPerformanceDiagnostic \
  -only-testing:HermesMobileTests/ChatViewModelStreamingPaceTests/testSyntheticLongStreamingPerformanceBaseline \
  -only-testing:HermesMobileTests/TranscriptMediaParserTests/testNoMediaTranscriptParsingPerformanceDiagnostic \
  > .codex-tmp/perf-baseline/logs/baselines.log 2>&1
rg '\[PERF\]' .codex-tmp/perf-baseline/logs/baselines.log
```

The dedicated scheme only enables `HERMEX_RUN_PERFORMANCE_BASELINES=1` for its
test action. The normal `HermesMobile` scheme skips the expensive repeated
50/500/5,000-message cache write diagnostic.

Fixture coverage:

- Transcript: newest 50 alternating messages with long prose, code, table,
  list, link, inline/display math, reasoning/activity, and three synthetic
  `MEDIA:` references.
- Streaming: 256-, 10,000-, and 50,000-character replies split by the fixed
  awkward-width sequence `1,7,2,19,3,31,5,11,23,4`; includes Unicode grapheme
  clusters, CRLF, repeated spaces, tabs, open/closed fences, tables, math, and
  media-like text inside and outside fences.
- Persistence: 50, 500, and 5,000 messages plus 40 sessions, all generated into
  fresh in-memory SwiftData stores.
- Images: repeated and unique 64-pixel and 2,048-pixel opaque/transparent/
  oriented images generated with UIKit in the test process.
- Git: 100-, 5,000-, and 25,000-line multi-hunk diffs.

Correctness assertions cover final byte-identical streamed content, fixture
sizes, parser results, fetch/object volumes, cache hits/misses/cost, parse
invocations/bytes examined, and main-actor execution. Timing is reported only
through `[PERF]` log lines and XCT activities.

## Inventory at baseline creation

- `TranscriptPerformanceSignpost` already bracketed transcript cache fetch,
  mapping, cache-first publication, reconciliation, and first committed frame.
  It previously logged public session IDs; payloads are now count-only.
- `TranscriptDisplayModelTests` already contained the hosted first-frame and
  display-model microbenchmarks plus the lazy-row guard.
- `ChatViewModelStreamingPaceTests` and `StreamingWordDrainTests` already
  covered cadence, catch-up, completion flushes, byte-identical Unicode output,
  unit boundaries, and quotas; they did not report operation volume or update
  cost.
- `CacheStoreTests` already covered cache semantics and newest-50 reads,
  including an optional developer-store path. The shared baseline never uses
  that real-store option.
- `TranscriptMediaParserTests` already contained the exact-marker no-media
  benchmark and fenced-marker correctness tests. The media-preview tests
  covered authenticated/public loading, decode fallback, export, and errors,
  but not cache growth/hit volume.
- `GitWorkspaceViewModelTests` already covered small and multi-hunk parser
  correctness. It had no large deterministic fixture or invocation counter.
- Image-preview/downsampler tests already checked pixel bounds and cancellation;
  generated repeated/unique transparency/orientation stress was missing.
- No committed `xctrace` workflow or Instruments runbook existed. The standard
  installed templates on the capture host included Time Profiler, SwiftUI,
  Animation Hitches, and Allocations.

## Stage-specific Points of Interest

Use the `pointsOfInterest` category and filter these names:

| Path | Signposts/counters |
| --- | --- |
| Transcript open | `Transcript cache fetch`, `Cached message mapping`, `Cached messages ready off-main`, `Cache-first publication`, `First synchronous transcript layout`, `First transcript frame committed`; visible row evaluations are reported by the transcript test |
| Cache write | `Cache write total`, `Cache write reconciliation`, `Cache maintenance`, `Cache save`; fetches and fetched/updated/inserted/deleted counts are reported by the test |
| Streaming | `Streamed token buffering`, `Paced stream drain`, `Stream message publication`; Debug counters report updates, characters buffered/published/scanned, and publication p50/p95 |
| Rich transcript | `Transcript media segmentation`, `Math segmentation`, `Markdown view update`; first synchronous layout and Core Animation commit bracket the first-frame layout/commit stages |
| Images | `Image cache lookup hit`, `Image cache lookup miss`, `Image load`, `Image decode`, `Image decode and downsample`; Debug snapshots report entries, decoded byte cost, hits, and misses |
| Git diff | `Git diff parse`; Debug counters report invocation count and bytes examined across repeated view updates |

## Current measurements

Host for the July 23, 2026 automated capture: Mac mini (Mac16,10), Apple M4
(10 cores), 24 GB RAM; macOS 26.5.1 (25F80); arm64 Mac Catalyst Debug; three
warm-ups and 15 samples; synthetic fixtures; no server/network.

| Scenario | Result |
| --- | --- |
| Hosted 50-message historical baseline | 26.21 ms median to committed frame; 22.24 ms through synchronous layout |
| Most recent pre-instrumentation hosted result | 25.38 ms committed; 22.54 ms synchronous layout; 5 of 50 rows evaluated |
| Synthetic rich 50-message first frame | 28.46 ms median / 30.14 ms p95 committed; 26.09 ms median / 26.67 ms p95 synchronous layout; 4 of 50 rows evaluated in every sample |
| Streaming, 256 characters | 29 paced publications; 0.010 ms p50 / 0.035 ms p95 publication; 7,096 characters copied/scanned; final content correct |
| Streaming, 10,000 characters | 96 paced publications; 0.017 ms p50 / 0.041 ms p95 publication; 4,934,274 characters copied/scanned; final content correct |
| Streaming, 50,000 characters | 127 paced publications; 0.059 ms p50 / 0.158 ms p95 publication; 118,953,425 characters copied/scanned; final content correct |
| Cache write, 50 messages | Cold 10.13 ms median / 10.57 ms p95; warm update 11.70 / 12.30 ms; 54 fetches; cold inserted 50/fetched 150, warm updated 50/fetched 240, 0 deleted; total is main-actor duration |
| Cache write, 500 messages | Cold 215.51 ms median / 220.44 ms p95; warm update 225.21 / 228.80 ms; 504 fetches; cold inserted 500/fetched 1,500, warm updated 500/fetched 2,040, 0 deleted; total is main-actor duration |
| Cache write, 5,000 messages | Cold 17,099.64 ms median / 28,608.09 ms p95; warm update 14,995.66 / 26,168.87 ms; 5,004 fetches; cold inserted 5,000/fetched 15,000, warm updated 5,000/fetched 20,040, 0 deleted; total is main-actor duration |
| Cached transcript open, 50 messages | Cold 1.083 ms median / 287.561 ms p95; warm 1.081 / 21.899 ms; cached-offline 1.091 / 1.432 ms |
| Cached transcript open, 500 messages (newest 50) | Cold 1.209 ms median / 236.310 ms p95; warm 1.211 / 6.006 ms; cached-offline 1.237 / 1.631 ms |
| Cached transcript open, 5,000 messages (newest 50) | Cold 1.557 ms median / 1.755 ms p95; warm 1.544 / 1.843 ms; cached-offline 1.577 / 1.755 ms |
| Image stress | 4 entries; 25,198,592 decoded-byte cost; 4 misses then 4 hits; cold decode 0.123 ms median / 0.725 ms p95; warm lookup 0.028 / 0.047 ms; large-image downsample 1.162 / 1.241 ms |
| Git diff parse, 100 lines | 0.089 ms median / 0.102 ms p95 |
| Git diff parse, 5,000 lines | 4.149 ms median / 4.210 ms p95 |
| Git diff parse, 25,000 lines | 21.186 ms median / 21.429 ms p95; 54 total invocations across all sizes including warm-ups |
| Exact-marker no-media parser | Historical 44.50 ms median per 100 passes, improved to 4.58 ms (about 90%); retain the exact `MEDIA:` fast path |

Cache write/open measurements are emitted by the same command. Copy values only
from completed `[PERF] CacheBaseline` and `[PERF] CacheOpenBaseline` lines; do
not infer them from another machine or from a partial result bundle.
The 50- and 500-row open p95 values include test-host scheduling outliers while
their medians and cached-offline p95 remain near 1 ms; this is why these numbers
are diagnostic evidence, not CI thresholds.

Known interpretation: rich Markdown layout remains the leading first-frame
cost. Do not repeat the rejected scroll-observer, vertical-axis-guard,
paragraph-`fixedSize`, plain-text-substitution, or generic Markdown-preparse
experiments.

## Manual Instruments capture

Build the signed app (never add `CODE_SIGNING_ALLOWED=NO`):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build \
  -project HermesMobile.xcodeproj \
  -scheme HermesMobile \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath .codex-tmp/perf-baseline/ManualDerivedData \
  > .codex-tmp/perf-baseline/logs/signed-debug-build.log 2>&1
codesign --verify --deep --strict \
  .codex-tmp/perf-baseline/ManualDerivedData/Build/Products/Debug-maccatalyst/Hermex.app
open -n .codex-tmp/perf-baseline/ManualDerivedData/Build/Products/Debug-maccatalyst/Hermex.app
```

In Instruments, attach to `Hermex` and run the identical scenario after three
warm-ups. Save every trace below `.codex-tmp/perf-baseline/traces/`.

For repeatable command-line attachment after launching the app, substitute the
template and output name as needed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun xctrace record \
  --template 'Time Profiler' \
  --attach Hermex \
  --time-limit 30s \
  --output .codex-tmp/perf-baseline/traces/time-profiler.trace
```

1. **Time Profiler:** record total and main-thread CPU; inspect the named
   signpost intervals and their call trees.
2. **SwiftUI:** record view body updates, layout, and repeated row evaluations.
3. **Animation Hitches / Core Animation:** record first-frame commit time,
   hitch count/duration during streaming, image reveal, and diff interactions.
4. **Allocations:** record peak resident memory and persistent growth for the
   5,000-message and image-stress scenarios; mark the post-warm-up generation.
5. **Points of Interest:** add the instrument from the library and filter the
   stage names above. Confirm payloads contain counts only.

For Git diff, capture initial load, collapse all, expand all, resize the window,
then change appearance; report parse duration and invocation count for each
step. For transcript open, capture cold-cache, warm-cache, and cached-offline
separately. For images, capture cold unique loads, repeated warm loads, and
large-image downsampling. For streaming, capture the complete 50,000-character
fixture through final correctness.

Each manual result note must include Mac model/chip, OS/build, Debug
configuration, fixture identity, warm-up/sample count, cache state, and
`server/network: yes|no`. If a configured server is used for the manual app
flow, use synthetic content and state that explicitly; never include its URL or
credentials in the note.

## Metrics not yet automated

- Total main-thread CPU and frame-hitch count/duration for streaming require a
  Time Profiler plus Animation Hitches capture.
- Peak resident memory requires Allocations or VM Tracker; decoded image cost is
  automated, RSS is not.
- SwiftUI body/layout attribution below the stage boundaries requires a SwiftUI
  Instruments trace.
- Git diff collapse/expand, resize, and appearance-triggered invocation counts
  require the manual UI sequence; parser-only timing and invocation volume are
  automated.
- Cache maintenance duration is available in Points of Interest, but XCTest does
  not yet export it as a numeric percentile.

These gaps are intentionally marked unavailable until a trace is captured; no
values should be fabricated.
