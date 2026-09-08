# Integrated Mac performance validation — September 7, 2026

The candidate preserves July's bounded streaming buffer and background cache
writer, adds deterministic image retention and eliminates repeated Git parses.
It does **not** demonstrate a universal speedup over the already-optimized
pre-modernization fork. New upstream features add some measured overhead;
visible interaction, energy and display stability still need the unlocked Mac.
Keep Catalyst. The evidence supports targeted app work and validation, not a
native rewrite.

## Included work and controlled comparison

Before: `6ceaa5c`, an isolated detached copy of the fork before window/upstream
modernization, already containing July's streaming/cache improvements.
Candidate app code: `5ae5492` and its ancestors (stable upstream integration,
window, connection status, bounded images, prepared Git rows). Later validation
changes add test/report files only. The alternate Mac idiom was rejected after
a verified runtime exception; the default platform mode remains unchanged.

Both signed arm64 Catalyst Debug variants were built with Xcode 26.6 and coverage
disabled on this Mac M4/24 GB, macOS 26.6.2 (25G83). The old variant was cleanly
rebuilt after an initial misdirected build left incompatible intermediates;
only the successful clean build/results are used. No historical timing was
substituted for this current comparison. Package lock revisions are unchanged.

The existing `HermesPerformanceBaselines` scheme ran serially with the same
`hermex-synthetic-performance-v1` fixtures. Cache, parser and hosted-frame cases
use three warmups and 15 samples. Streaming totals were additionally measured
in five fresh test processes per variant; their p95 below is the maximum of five.
Profiler runs are separate from timing runs. These fixtures use no server or
user transcript. Display/scene conditions varied during the broader session,
so these are algorithm/hosted-fixture comparisons, not a fixed-display GUI A/B.

## Paired results

Times are milliseconds, median / p95 unless stated otherwise.

| Scenario | Before | Candidate |
| --- | ---: | ---: |
| Cache write 50, cold | 4.355 / 4.628 | 4.693 / 4.907 |
| Cache write 500, cold | 42.485 / 43.678 | 45.119 / 52.063 |
| Cache write 5000, cold | 423.674 / 433.737 | 452.674 / 461.780 |
| Cache write 5000, warm | 415.321 / 429.353 | 449.850 / 459.955 |
| Main-thread capture for 5000-row write | 0.00167 / 0.00279 | 0.00125 / 0.00238 |
| Newest 50 cached rows from 5000, cold open | 1.482 / 1.500 | 1.584 / 1.682 |
| Same read, warm | 1.486 / 1.515 | 1.589 / 1.638 |
| Same read, cached-offline fixture | 1.503 / 1.516 | 1.602 / 1.651 |
| Hosted rich transcript committed frame | 13.503 / 14.299 | 15.019 / 15.643 |
| Hosted synchronous layout | 12.111 / 12.961 | 13.021 / 13.537 |
| Rows evaluated from 50 | 4 | 8 |
| Raw Git parser, 100 lines | 0.088 / 0.096 | 0.087 / 0.094 |
| Raw Git parser, 5000 lines | 4.163 / 4.277 | 4.161 / 4.291 |
| Raw Git parser, 25000 lines | 21.157 / 21.659 | 21.137 / 21.254 |

Warm cache writes still use two fetches and run outside MainActor. Maintenance
cost is zero in this fixture because there is no expired data to purge; that
is not a claim that real maintenance is free. The candidate persists additional
turn metadata and renders a denser upstream transcript. The results show a
roughly 7–8% write-time increase and a 1.5 ms hosted first-frame increase while
more rows are evaluated; they do not establish a single cause or a real-window
frame-rate regression. Neither motivates undoing correctness/feature changes.

| Repeated paced-stream total | Before | Candidate |
| --- | ---: | ---: |
| 256 characters | 65.329 / 72.261 | 134.082 / 135.680 |
| 10000 characters | 173.155 / 177.711 | 184.191 / 185.302 |
| 50000 characters | 281.240 / 282.078 | 286.700 / 289.844 |
| 50000 final input event to visible content | 264.349 / 265.583 | 270.360 / 273.417 |

All runs finish byte-identically. Copied/scanned counts remain 7,538 / 150,554 / 
321,426 respectively, with 29 / 96 / 127 paced publications. For 50k, the median
across runs of publication p50/p95 rises from 0.090/0.178 ms to 0.115/0.250 ms.
The short-case extra wait is reproducible in this harness and remains a follow-up
measurement concern. Totals include intentional 1 ms pacing, coalescing, task
wakeups and test observation; they are not pure CPU duration or network latency.
No unsupported cadence change was made merely to lower this number.

The July report compared the old published implementation's 118,953,425 scanned
characters with 321,426 after optimization. That algorithmic improvement remains
present here. Historical wall-clock gains are not relabeled as new gains from
this modernization.

## Images and incremental Git work

The paired four-image fixture retains 25,198,592 decoded bytes in both versions.
Its cold median/p95 changes from 0.135/0.544 to 0.761/16.236 ms; warm from 0.023/0.036
to 0.105/0.117 ms. The old UIImage initializer could defer pixel decoding; the new
path eagerly creates a bounded ImageIO thumbnail before publication. Four images
are too few to infer a general latency win. Earlier focused image timings also
varied substantially with host state. The defensible benefit is bounded retained
pixels and controlled decoding, with visible scrolling still unmeasured.

The new 48-unique-4K fixture reaches a stable 60 MiB decoded cache, five entries,
43 evictions, 48 misses and48 warm hits. The observed process resident high-water
mark reaches 589,578,240 bytes, including fixture/framework/test allocations; it
is not a cache limit or an old/new RSS comparison. See the image report for caps,
alpha/orientation and cancellation evidence.

Within the integrated upstream review surface, eight 5000-line responses previously
caused 36 parses as files arrived. Prepared rows reduce this to eight; matched
median/p95 incremental work changes from 1733.564/1745.596 to 390.713/403.752 ms.
Twenty unchanged rebuilds add zero parses, including the 25000-line case, with
zero main-thread parser calls. This reduces repeated computation, not server
latency. See the dedicated Git report.

## Current profiler evidence

A 20-second Time Profiler capture of repeated synthetic streaming yields 7,274
running samples (1 ms weights), 5,389 on the main thread. Nearest-application-frame
groups include `StreamingWordDrain.splitAtUnitBoundary` 4.41%, ChatMessage equality
3.64%, `StreamingTextBuffer.append` 3.20%, reasoning-display grouping 1.99%, token
publication 1.65% and turn classification 1.46%. These are shares of sampled running
weight, not end-to-end response time. Test observation polling appears in 3.49%
of inclusive stacks. No single measured stack establishes the cause of the
short-case extra wait.

A separate 20-second hosted-transcript trace contains 20,902 running samples,
20,090 on the main thread. Inclusive `_UIHostingView.layoutSubviews` stacks cover
69.35%; CoreText CTLine-family stacks 8.20%. Nearest application frames include
link-preview URL extraction 2.38%, skip-line handling 1.88%, transcript-block
equality 2.31%, attachment-marker parsing 0.80% and media segmentation 0.76%.
Inclusive percentages overlap and must not be summed. This identifies specific
remaining work instead of attributing everything vaguely to SwiftUI.

An Allocations recording also completed, but its CLI export inventory exposes no
allocation-size/lifetime table. It is retained for Instruments inspection; no
allocation-total or leak-free claim is made. Normal SwiftUI/Animation Hitches,
energy, resize, scroll and second-display traces remain pending an unlocked,
stable desktop. The synthetic hosted layout trace cannot replace those checks.

## Next investment and architecture decision

1. Complete the visible window/status/transcript/media regression matrix and
   capture a stable-display scrolling/resize trace. This has highest confidence
   and release value; no further code redesign is needed to start it.
2. Instrument first-token/first-publication and wakeup delay to explain the
   short-response harness increase before changing pacing. The measured CPU
   stacks and unchanged operation counts do not yet isolate its cause.
3. If real scrolling confirms the hosted profile, investigate repeated
   link-preview extraction and transcript equality/group derivation with
   bounded per-message reuse. Keep content, selection and late-update correctness.
4. Revisit the alternate Mac idiom only after replacing/guarding unsupported
   refresh controls and executing its full UI matrix. No adoption benefit is
   established, and broad remediation is outside this experiment.

Stay with Catalyst. No required capability has been shown to demand an AppKit
rewrite, and the demonstrated image/Git fixes are app-level improvements.
A native prototype would need an independently identified blocker and a matched
A/B threshold (for example 20–30% sustained improvement in that blocked metric)
before a migration is justified. Native SwiftUI alone does not guarantee that
Markdown/text layout costs disappear.

## Verification and retained evidence

Final full Mac suite: 2367 total, 2362 passed, 5 expected skips, 0 failures.
Final full iPhone suite: 2365 total, 2360 passed, 5 expected skips, 0 failures.
The explicit live read test also passes; eleven maintenance checks pass.
Signed Mac bundles verify. Normal-app manual checks remain pending desktop
unlock and the second Mac/display where applicable; affected PRs remain draft.

Full logs, before/candidate builds, repeated-stream summaries, results and traces
are retained under `.codex-tmp/mac-modernization/`. Principal results:
BeforeModernizationBaselines, IntegratedBaselines, BeforeStreamingRepeated,
IntegratedStreamingRepeated, ValidationMacFull, ValidationIPhoneFull;
IntegratedSyntheticTimeProfiler, IntegratedTranscriptTimeProfiler and
IntegratedTranscriptAllocations traces. Do not remove these as rebuildable
clutter. A failed initial profiler attachment (the short test had already ended)
was corrected with a synchronized test/profiler launcher; only completed captures
are analyzed above.
