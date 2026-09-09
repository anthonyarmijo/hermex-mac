# Direct chat text selection — September 8, 2026

Issue #28 adds direct primary-button dragging within one user message or one
completed assistant response, adapting upstream Hermex #456. It retains the
existing Markdown rendering, bounded image providers, Mac interface idiom and
server contracts. No production chat was sent, edited or deleted in validation.

## What changed

The previous check in NORMAL_APP_VALIDATION_2026-09-07.md covered the separate
Select Text window. It did not establish in-transcript mouse dragging. The
preserved signed candidate at `1eaa41c` reproduced no highlight on a two-line
assistant-text drag. Upstream's native selection alone supported a word gesture
but did not supply Mac range dragging.

The Mac adapter uses primary-pointer gestures and UIKit selection display, with
one selection owner per message. iPhone retains UITextInteraction touch handling.
A per-chat focus scope stops the Mac background-tap handler from immediately
refocusing the composer after word selection, including its deferred focus task.
Selected-text menus avoid snapshotting a whole long response. Copy/More controls
retain full-message actions, including disabled mutation rules while streaming
or viewing cached data.

Glyph ranges expand complete UTF-16 composed sequences. Inline chip pictures
occupy a rendering coordinate but are omitted from selection text; later text
and terminal emoji remain correctly aligned. Message ID, content, session/server
media namespace and timestamp participate in selection invalidation. Leaving
first responder clears the old range; scope references are weak and per chat.

## Native Mac checks

Used a signed Debug Mac app with separate `benchmark.candidate` bundle, Keychain
and app-group identities, against a loopback-only deterministic fixture. Its
request handler rejects mutations. The owner's app/data were not used by tests.
CUA screenshots and accessibility observations are retained in the task.

- Drag selection spans formatted paragraphs, lists and code. Command-C followed
  by pasting into the unsent fixture composer produced exactly the selected
  content, including emoji, combining accents, Hebrew and Arabic.
- Command-A highlights only the active assistant response: headings, text, code
  and table cells. Copied tables retain tabs between cells and newlines between
  rows; the neighboring user message, image/link previews and controls are absent.
- User-bubble dragging and message-scoped Select All copied both original text
  lines and Unicode content. All pasted fixture drafts were cleared without sending.
- Double-clicking a word while the composer had focus retained selection. The
  selected-text context menu offered Copy/Select All; Copy pasted exactly `formatted`.
- Moving between user/assistant selection and the composer cleared old ranges.
  More retained Listen, Regenerate Response and Fork From Here.
- Resizing kept highlights aligned. An inline link opened the expected Example
  Domain page in the external browser; the fixture-only browser tab was closed.

## Automated validation

Signed test hosts use separate `benchmark.validation` identities. The Mac test
host's resolved bundle and Keychain group were verified before execution. The
simulator uses a separate app bundle and configured Keychain service; no signing
was disabled. The empty normal simulator codesign entitlement dump is not used
as evidence of a Developer ID profile or real-device entitlement validation.

Tests cover real rendered Markdown registration, headings/lists/code/tables,
excluded equations and controls, hosted registration, message boundaries,
streaming exclusion, identity reset, Unicode/RTL, inline chips, pointer range
extension, word selection, per-chat focus handoff and first-responder reset.
Final Mac suite: **2,383 total; 2,378 passed, 5 expected skips, 0 failures**
(`FinalMac.xcresult`). Final iPhone 17 / iOS 26.5 suite: **2,380 total; 2,375
passed, 5 expected skips, 0 failures** (`FinalIPhone.xcresult`). Five skips are
opt-in live-server/performance and photo/video integration checks.

Commands: signed isolated `xcodebuild build-for-testing`, then
`xcodebuild test-without-building -enableCodeCoverage NO` for each platform.
XcodeBuildMCP was unavailable. Xcode 26.6, macOS 26.6.2, M4 / 24 GB.
Full build logs and result bundles are preserved locally under
`.codex-tmp/mac-modernization/text-selection/`.

## Long-history release blocker

**Performance validation is not green.** Tracked in
[issue #29](https://github.com/anthonyarmijo/hermex-mac/issues/29). In the 512-message deterministic
fixture, a jump to latest, session reopening or composer collapse can leave
the application unresponsive at approximately 100% CPU. This happened in the
selection build and in the preserved PR #26 code build (`1eaa41c`). The baseline
reproduction establishes that a similar hang predates this adaptation; it does
not establish equal incidence or exclude amplification by the selection host.

Candidate PID 87534's three-second sample had all 1,625 main-thread samples
inside the SwiftUI update/layout path, including LazyStack row estimation.
Physical footprint was 240.6 MB, peak 357.9 MB. Baseline PID 93723 also stalled;
its independent two-second sample is preserved. These are runtime samples,
not just UI-automation timeouts. Only isolated test processes were force-quit.

Controlled experiments with size anchors, row containers, broad transcript
animation, content margins, unanchored tail scrolling, bounded UIKit scrolling,
and a one-column lazy grid did not reliably prevent recurrence. None is retained
in this PR. An eight-second SwiftUI trace reported no SwiftUI data; it is excluded
from causal/performance conclusions. The samples remain useful. Similar public
[layout-loop investigations](https://tacticremote.com/blog/2026-07-03-hunting-a-swiftui-layout-livelock/)
suggest a framework interaction but do not prove the same cause here.

The baseline completed four warm session-reopen trials (3,399 / 3,160 / 3,132 /
3,127 ms) and four width-resize cycles (2,485 / 2,486 / 2,516 / 2,666 ms), with
all observations containing message 512. Resize captures verified 1024×686 →
864×686 → 1024×686. Timings include clicks and accessibility/screenshot tool
latency, not intrinsic app latency or FPS. Unsuccessful candidate comparisons
are not a performance pass or an improvement claim.

During the row-container experiment, long-message selection stayed aligned
through four resize cycles; four image-scroll cycles returned to image 24 and
its preview opened successfully. Those observations are supplemental only:
that experimental container is not the final source. Repeat these checks on
the eventual hang correction before promotion.

## Remaining equipment checks

The 1.2.0 build 2 comparison installer includes selection but is not release-ready.
After resolving the long-history blocker, consolidate the final
physical-display/scale/disconnect, spoken VoiceOver and second-Mac installation
and server-connection checks. These remain owner checks, not automated passes.
The previously approved release sequence resumes once they pass; this fix does
not authorize or perform a backend upgrade.
