# Streaming render performance

## Scope and measurement contract

This slice uses the `hermex-synthetic-performance-v1` fixture and the same host
and arm64 Mac Catalyst Debug configuration recorded in `BASELINE.md`. Automated
fixtures use no server or network. Raw logs, result bundles, and traces live in
`.codex-tmp/streaming-render-performance/` and are intentionally uncommitted.

The deterministic stream includes awkward token boundaries, ZWJ emoji, flags,
combining marks, CRLF, tabs, repeated whitespace, Markdown fences, tables, math,
and `MEDIA:`-like text. Every run asserts byte-identical final UTF-8 output.

## Buffer findings and change

The old normal-token path joined all pending chunks and appended them to the
already-visible response before replay dedup immediately learned that the
connection was not replaying. Each drain tick then joined the backlog once to
count units and again to split it. The 50,000-character fixture consequently
reported 118,953,425 copied or scanned characters.

`StreamingTextBuffer` now:

- scans only the arriving token to update word-unit state;
- coalesces tiny tokens into bounded ~2,048-character storage chunks;
- retains per-chunk unit contributions and drains only enough leading chunks to
  cross the requested word boundary;
- materializes the full pending response only while replay dedup is armed;
- preserves `StreamingWordDrain` as the final Character/grapheme-safe splitter;
- supports full flush, reset, and exact replay visibility.

Normal non-replay appends no longer construct or scan the full effective
response. Replay behavior still compares flushed plus pending content and is
covered by the reconnect/recovery suites.

## Automated before and after

The before result is
`.codex-tmp/streaming-render-performance/pre/results/streaming-baseline-with-latency.xcresult`;
the final result is
`.codex-tmp/streaming-render-performance/final/results/streaming-final.xcresult`.

| Characters | Metric | Before | After |
| ---: | --- | ---: | ---: |
| 256 | paced updates | 29 | 29 |
|  | publication p50 / p95 | 0.0085 / 0.0206 ms | 0.0101 / 0.0486 ms |
|  | stream elapsed | 65.59 ms | 67.20 ms |
|  | final event to visible | 65.44 ms | 67.05 ms |
|  | copied/scanned characters | 7,096 | 7,538 |
| 10,000 | paced updates | 96 | 96 |
|  | publication p50 / p95 | 0.0148 / 0.0314 ms | 0.0155 / 0.0353 ms |
|  | stream elapsed | 198.54 ms | 180.35 ms |
|  | final event to visible | 180.19 ms | 178.22 ms |
|  | copied/scanned characters | 4,934,274 | 150,554 (96.95% lower) |
| 50,000 | paced updates | 127 | 127 |
|  | publication p50 / p95 | 0.0585 / 0.1346 ms | 0.0870 / 0.1396 ms |
|  | stream elapsed | 698.04 ms | 280.27 ms (59.85% lower) |
|  | final event to visible | 310.74 ms | 267.24 ms (14.00% lower) |
|  | copied/scanned characters | 118,953,425 | 321,426 (99.73% lower) |

The 50,000-character publication p95 changed by 0.005 ms while total stream
time and completion latency improved materially. The higher small-fixture
microsecond values are the bounded buffer's fixed bookkeeping cost; they remain
well below one frame and do not change the paced update count.

The performance test now fails deterministically if 50,000-character app-owned
buffer volume exceeds 500,000 characters. It deliberately does not enforce a
wall-clock CI threshold.

## Renderer evidence and bounded change

The signed app was launched with its debug-only, server-free
`--streaming-lab` entry point under Time Profiler. The 15.94-second
launch-and-replay capture sampled 627 ms total CPU and 505 ms main-thread CPU.
The dominant sampled stacks were layout and commit:

- `UIView.layoutSublayersOfLayer`: 209 ms inclusive;
- `_UIHostingView.layoutSubviews`: 139 ms;
- SwiftUI `LayoutProxy.dimensions(in:)`: 85 ms;
- `LayoutEngineBox.sizeThatFits`: 72 ms;
- stack placement/resize: roughly 63–69 ms each.

App math/media functions and cmark parsing did not appear as sampled hotspots;
layout remains the leading bounded next target. The SwiftUI trace reported no
SwiftUI data, and its hitch tables contained zero rows. The Allocations trace
could not attach because Instruments marked the Catalyst target restricted
under SIP, so peak RSS is unavailable. No before trace existed for CPU, hitch,
or RSS comparison; those fields are explicitly unavailable rather than inferred
from elapsed XCTest time.

The renderer change is therefore intentionally small: when content contains
neither `$` nor a backslash, math segmentation returns the original Markdown
without allocating `Array(content)`, constructing fenced/inline protection
masks, scanning display delimiters, or repeating inline-math replacement. Every
supported math delimiter contains one of those two characters, so delimiter-
bearing content remains on the existing path. A byte-equality test covers prose,
links, tabs, CRLF, emoji, and repeated spaces.

## Candidates retained or rejected

- The exact `MEDIA:` marker fast path is retained unchanged.
- Streaming already isolates settled ~6,000-character chunks behind conservative
  blank-line, heading, thematic-break, and closed-fence boundaries. No second
  prefix splitter was added.
- A retained streaming-message array index was not added: the trace did not show
  the linear lookup as material, while keeping it valid through load, merge,
  recovery, pagination, and ID replacement would widen correctness risk.
- No parsed-Markdown cache was added. The trace points to layout, and a cache
  would add invalidation and memory cost without evidence of p95 improvement.
- Publication cadence, animation, Markdown fallback policy, text selection,
  links, and bottom-follow behavior are unchanged.

## Verification evidence

- Buffer/pace suite: 30 tests, 0 failures.
- Streaming, Markdown math, and transcript-media suite: 87 tests, 0 failures.
- Reconnect/replay, coordinator, send/snapshot/completion/error, scroll,
  streaming splitter, and fade suite: 242 tests, 0 failures.
- Signed arm64 Mac Catalyst Debug build succeeded and passed
  `codesign --verify --deep --strict`.
- Full signed Mac Catalyst suite: 1,518 executed, 2 expected performance
  skips, 0 failures (`test-without-building` reused the final signed bundle
  after Instruments caused the login keychain to lock).
- Current Mac app/test sources: unsigned compile-only `build-for-testing`
  succeeded with coverage disabled; the resulting app was not launched.
- iPhone 17 shared-source compile-only build succeeded with signing disabled;
  the resulting app was not installed or launched.
- Signed `--streaming-lab` launches exercised prose, headings, flat/nested lists,
  fenced Swift code, word-paced reveal, fade, completion linger, and tail follow
  without server/network access.

## Remaining hotspot and next experiment

Layout/commit dominates the captured renderer cost. A future bounded experiment
should measure whether MarkdownUI can retain layout for demonstrably closed,
settled blocks without changing paragraph geometry, selection, links, tables,
or scroll anchors. It should be rejected unless a SwiftUI trace records real
update data and p95 frame/update cost improves with a strict memory bound.
