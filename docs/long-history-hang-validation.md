# Long-history hang investigation — issue #29

Status: candidate fix, native validation incomplete. Do not promote Mac 1.2.0
on the strength of the unit suite alone.

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
- Full Mac suite: 2,382 passed, 5 skipped, zero failures (2,387 total).
- Native validation of that exact build is waiting for the Mac to be unlocked.
  No claim of a completed performance comparison or fixed release blocker yet.

Logs, source snapshots, samples and result bundles are retained locally under
`.codex-tmp/mac-modernization/long-history-fix/`. `FullMac.xcresult` and
`FocusedMac2.xcresult` contain the successful test runs. The signed UI identity is
`com.anthonyarmijo.hermex.benchmark.candidate`; the test identity is
`com.anthonyarmijo.hermex.benchmark.validation`. Owner login and chats are not
test fixtures. Prior signed installers and profiling builds remain preserved.

## Required before leaving draft

1. Repeat long-history reopening, composer collapse, resizing, scrolling and
   selection with the restored observer hooks. Compare against preserved PR #26
   and selection build 2; investigate hangs or material regressions.
2. Verify following versus reading older history, the latest-message button,
   prepend position, disclosure positioning, cache-first display and streaming
   completion. Confirm row recycling does not steal selection or composer focus.
3. Repeat real pointer selection and copied-content checks across Unicode,
   paragraphs, lists, code and tables; verify links, image previews, message menus,
   keyboard copying and selection reset on session/server changes.
4. Complete corrected-candidate display/scale/disconnect, spoken VoiceOver and
   second-Mac installer/server checks before the approved release sequence.

No backend, network or service changes are part of this fix. The accepted Mac
testing policy requires no iPhone suite for this Mac-only container change.
