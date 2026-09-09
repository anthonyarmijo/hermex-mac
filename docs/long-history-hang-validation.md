# Long-history hang investigation — issue #29

Status: automated and controlled native checks passed, with brief layout stalls
documented below. Corrected installer equipment checks remain before promotion.

## Reproduction and candidate

A controlled, loopback-only fixture contains 512 alternating user/assistant
messages with paragraphs and code. Reopening it, jumping to the latest message,
and collapsing the composer reproduced a main-thread hang near 100% CPU in both
the preserved PR #26 app and the selection candidate. Samples repeatedly show
SwiftUI/AttributeGraph `LazyStack` `measureEstimates` work. This establishes that
the problem predates text selection; it does not establish that selection has
no effect on its severity.

Explicit viewport height and suppressing transcript animations also hung. Their
changes were reverted. The current Mac-only alternative uses native `List` cell
virtualization while retaining the existing message views, rendered-text
selection and bounded image providers. The shared iPhone layout is unchanged.
Visible row probes share one scroll observer, so recycling a cell does not
disconnect the rest of the transcript or add duplicate follow-gesture handlers.

## Evidence so far

- The initial List experiment completed six reopen/collapse trials and narrow/
  wide resizing and wheel scrolling without hanging. These trials preceded
  restoration of scroll-observer hooks and are preliminary evidence only.
- The signed isolated Mac build with observer hooks compiles successfully.
- Focused scroll, observer-lifecycle and text-selection tests pass. One initial
  assertion ran before deferred metric delivery; the test now awaits the actual
  callback and verifies continued delivery after a cell is recycled.
- A hosted test of the actual 512-message transcript reaches the latest row,
  evaluates fewer than 128 distinct message rows, and continues delivering
  metrics after scrolling. It waits for rendering/metric callbacks rather than
  assuming a fixed delay. This checks container wiring and bounded rendering,
  not real pointer interaction or comparative performance.
- The combined candidate includes merged auth isolation PR #35. Full Mac suite:
  2,384 passed, 5 skipped, zero failures (2,389 total).
- After unlock, the signed candidate exposed a cache-first positioning bug:
  the initial 50-message render reached its tail, but replacing it with all 512
  messages moved the reader back around message 50. Temporary geometry logging
  showed List refining both height and offset and falsely disabling follow.
  Non-gesture scroll-away detection now requires stable content/viewport sizes
  and an actual upward offset change. Temporary logging was removed.
- The corrected candidate automatically reached message 512 on four controlled
  openings, including three repeated reopen/composer-collapse trials. Wheel
  scrolling back to messages 506–508, narrowing from 1,024 to 864 points and
  widening again retained those messages; the latest button returned to 512.
  No hang occurred. CUA round-trip times are not app performance measurements.
- Real primary-button dragging selected text inside both user and assistant
  messages. Assistant copying preserved Unicode (emoji, combining characters,
  Hebrew and Arabic), paragraphs, lists, code, and tab/newline table structure.
  Selected-text context Copy/Select All and keyboard Cmd-C/Cmd-A worked after
  focus/menu transitions settled. Select All stayed within one message and
  excluded language labels and the link-preview chip. Synthetic pasted drafts
  were cleared without sending.
- Session switching cleared the visible selection. The assistant More menu
  showed Listen/Regenerate/Fork; the inline link opened example.com in Chrome.
  The 24-image transcript rendered and a media preview opened and closed.
  Native zoom filled the connected display, then restored the window.
- A separate loopback pagination server verified two real 50-message prepends
  (`msg_before=462` and `412`). Messages 463 and 413 respectively remained at
  the same vertical position, while their preceding responses became available.
  Switching to this server replaced the previous session list as expected.
- Updated focused Mac tests and full Mac suite pass: 2,385 passed, 5 skipped,
  zero failures (2,390 total). Results: `PositionFocusedMac.xcresult` and
  `PositionFullMac.xcresult`. The regression covers large height re-estimation
  with stationary, upward-adjusted, and forward-moving offsets.
- The clean signed build at `cfe8999` replayed a synthetic SSE response through
  the real chat path. Earlier completed text stayed selectable during streaming;
  the active response did not enter selection. After `done`/`stream_end`, primary
  dragging and Cmd-C copied its text. Completion kept the reader above the tail.
  Live reasoning expand/collapse and the completed-turn disclosure retained the
  surrounding reading position. Fixture contract follows the official
  [streaming reference](https://get-hermes.ai/api-docs/reference/chat-streaming/)
  and existing decoder tests; no model or production service was called.

## Corrected-candidate performance evidence

The preserved PR #26 and selection-build samples above establish sustained
unresponsive layout loops. Repeating their long-history reopen/composer/resize
workload on `cfe8999` no longer required force-quitting the test process.
An app-scoped 60.98-second Time Profiler recording on the same Mac captured three
additional reopen/shrink/expand cycles, wheel scrolling and selection across a
long response followed by resizing. All nine reopen/resize observations retained
message 512, and selection remained aligned after resizing.

Instruments reported five microhangs: 295.14, 271.86, 251.28, 276.01 and 262.60 ms.
Their sampled stacks involve native collection-cell creation, SwiftUI sizing and
text measurement, including `ResponseTextSelection.sizeThatFits`. No sampled
frame in this capture contains the former `measureEstimates` path. Each stall
ended and interaction continued; none was a sustained layout loop. These short
pauses remain a performance limitation and are covered by the release notes'
rich-Markdown caveat. This small Debug-build recording does not establish FPS,
release-build latency, equal workload per frame or a percentage speedup versus
the preserved builds. It supports resolution of the reproduced freeze, not a
claim that every long-chat pause is gone.

Retained evidence: `CorrectedNativeStress.trace`, its exported hang/sample XML,
`CorrectedNativeStress-summary.json` and `summarize-stress.py`, alongside the
earlier baseline and selection-build hang samples. Prior failing traces/builds
remain preserved. Build 3 increments only the Mac build number after this code.

Logs, source snapshots, samples and result bundles are retained locally under
`.codex-tmp/mac-modernization/long-history-fix/`. `IntegratedFullMac.xcresult` and
`IntegratedFocusedMac.xcresult` contain the final local test runs; the earlier
`FullMac.xcresult`, `FocusedMac2.xcresult` and `HostedListMac.xcresult` remain
preserved. The signed UI identity is
`com.anthonyarmijo.hermex.benchmark.candidate`; the test identity is
`com.anthonyarmijo.hermex.benchmark.validation`. Owner login and chats are not
test fixtures. Prior signed installers and profiling builds remain preserved.

## Required before leaving draft

1. Produce and verify the signed/notarized build 3 installer, preserving builds
   1 and 2. Controlled native passes above use an isolated development identity.
2. Complete corrected-candidate display/scale/disconnect, spoken VoiceOver and
   second-Mac installer/server checks before the approved release sequence.

No backend, network or service changes are part of this fix. The accepted Mac
testing policy requires no iPhone suite for this Mac-only container change.
