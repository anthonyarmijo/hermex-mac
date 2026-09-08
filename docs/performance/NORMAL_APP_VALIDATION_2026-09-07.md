# Normal Mac app validation — September 7, 2026

This follow-up uses the signed, normal Mac 1.2.0 candidate at app code `5ae5492`
(final validation commit `2a0bb38`), after the owner unlocked the desktop and
completed sign-in. It supplements the synthetic report. The media checks found a remaining
loader bypass, addressed on `issue/25-bounded-markdown-images` with the additional
verification below. Production-server settings were not changed.

## Verified normal behavior

- About confirms Mac version 1.2.0 (1). Main-window corner shrink/expand, native
  Fill, left-side tiling, full-screen entry and exit work with authenticated
  Home and chat content. The layout reflows and retains navigation and composer.
- A normally quit/relaunched process restores the large window, selected chat,
  sign-in and an unsent two-line draft. Shift-Return inserts a newline. The draft
  survives navigation away/back. Test text was removed through normal keyboard
  editing, and the empty composer/disabled Send were verified after navigation.
- The response Select Text action opens a native selection surface; double-click
  selects a word with both a visible highlight and an AX selected-text report.
- Connection status is reachable from the sidebar sheet and dedicated Settings.
  Both light and dark layouts show readable labels and version values; System
  appearance was restored after the temporary light check. URL copy was verified
  by pasting into a temporary local document, saved with ignored evidence.
- The real server reports Reachable and Signed in, with separate WebUI and agent
  versions, measured latency and refreshed check time. The loopback explanation
  states that localhost refers to the Mac running Hermex. Edit Server opens the
  existing server-details flow without changing its configuration.
- With the sheet focused, Tab/arrow navigation highlights the form actions and
  Space on Check Connection refreshes the timestamp and latency. AX exposes
  descriptive labels for the URL, copy, refresh, version and edit controls.
  Spoken VoiceOver output has not been verified.

## Normal transcript profile

A 45-second Time Profiler recording attached only to the normal candidate PID
87385 while a 64-message maintenance transcript was expanded, scrolled through
pointer input and resized. Its 3,211 weighted running samples include 3,158 on
the main thread. These weights are sampled running time, not frame-rate or
end-to-end latency. Time between manual actions and automation overhead are part
of the capture; it is not a continuous fixed-speed scroll benchmark.

The nearest non-entry-point app frames include reasoning-key normalization
(2.21% of running weight), tool-result JSON candidate extraction (1.78%) and
normalizing tool display strings (1.62%). Most stacks reach the generic app
entry point through framework work, so its large inclusive percentage is not
an actionable app function cost. No freeze or crash was observed during these
interactions. This does not establish a matched before/after smoothness gain.

Retained local evidence: `NormalAppScrollResize.trace`, exported profile XML,
`normal-app-scroll-resize-profiler-summary.json`, and the analyzer under
`.codex-tmp/mac-modernization/`. No transcript text or private addresses are
copied into this report.

## Temporary local fixture

The normal client was pointed at a separately named local validation server on
loopback port 18878. Its response shapes mirror the existing production decoder
fixtures. It contains synthetic sessions, procedural image pixels and Git diffs,
rejects mutation requests, does not proxy anything and reads no user files.
The fixture script, request log and mode input are retained in ignored evidence.
This exercises the normal app's UI; it is not evidence about a live backend's
mutation capabilities.

The connection UI verifies unavailable version fields while still reachable,
reachability separate from sign-in-required state with a Sign In action, an
unreachable explanation, last-known version labeling after a failed check, and
an actionable unexpected-response explanation. A delayed health response shows
Checking with refresh disabled, then a timeout explanation; restoring the
fixture returns the screen to Reachable.

## Markdown image correction (#25)

Remote Markdown images previously used MarkdownUI's independent block/inline
network loaders, bypassing the app's bounded media cache. Extensionless MEDIA
images also decoded through UIImage directly. Both now use the bounded cache;
Markdown keeps its existing parsing, alt labels and link behavior. Both Markdown
providers use the existing app transport and share the media cache namespace.
Server/session/auth identity changes recreate inline image tasks as well.

The signed normal app displayed 24 distinct procedural 4096 × 3072 images in an
expanded turn. Pointer scrolling reached the last image and returned to earlier
images; resizing preserved a readable layout. Named and extensionless MEDIA
images opened as images. The native export dialog saved the named original:
545,706 bytes, byte-identical to the fixture response, still 4096 × 3072, SHA-256
`560599e163e8e497071287348ec023958bd254ff729b93122283e3e5760f9d45`.

A 30-second Time Profiler capture attached to normal candidate PID 52600 during
image scrolling and resize. It contains 2,826 weighted running samples, 1,733 on
the main thread. Resampling is prominent in leaf samples; nearest app frames
include link-preview thumbnail generation (1.88%). This is evidence of the normal
path running, not a matched latency/FPS comparison or a process-memory ceiling.
`NormalAppImages.trace`, exported XML, summary, analyzer and export verification
are retained locally. The deterministic cache stress establishes retained cache
cost; visible views, originals, link metadata and other app allocations are
outside that cache budget.

Three new tests cover 4K downsampling/shared MEDIA hits, namespace isolation,
unsupported URL/cancelled-request rejection, and hosted MarkdownUI block/inline
transport injection. Full signed Mac: 2,370 total, five expected skips, zero
failures. Focused iPhone: 26 passed, zero failures. Strict signature verification
passed and the tested signed app was launched normally afterward.

Commands (all use the per-command Xcode developer path and coverage disabled):

- `xcodebuild test -project HermesMobile.xcodeproj -scheme HermesMobile -destination 'platform=macOS,arch=arm64,variant=Mac Catalyst' -enableCodeCoverage NO`
- `xcodebuild test -project HermesMobile.xcodeproj -scheme HermesMobile -destination 'platform=iOS Simulator,id=700E4D94-EC91-4A29-947E-B544482F2F6B' -enableCodeCoverage NO -only-testing:HermesMobileTests/BoundedImageCacheTests -only-testing:HermesMobileTests/TranscriptMarkdownImageTests`

Results: `MarkdownImagesMacFull.xcresult`, `MarkdownImagesIPhoneFocused.xcresult`.
Logs and derived products remain in the ignored validation directory.

## Git and restoration

The normal Git menu opened two synthetic files with 500 added and 500 removed
lines each. Diff rows rendered, pointer scrolling advanced line numbers, file
collapse exposed the next file, and dismiss/reopen worked. The staging-selection
sheet was also inspected without submitting an action. Line selection was not
established by these mouse attempts; deterministic selection tests remain the
evidence for that behavior. No stage/discard/commit/push or live mutation ran.

The original server was selected again and the temporary loopback service was
stopped. The generated, inactive Local validation fixture registry entry remains
available for reproducibility. The original server required another sign-in after
validation; the owner was asked to restore that session without sharing a password.
System appearance and the original server identity were preserved. No further
local app suite is planned after that sign-in.

## Remaining boundaries

A physical second-display move/disconnect and remote-Mac installation still need
owner equipment. Capture dimensions are rescaled by the automation tool, so
exact native frame/display point measurements are not asserted. A single fresh
process relaunch reached the initial populated accessibility observation in
2,092 ms including tool launch/IPC/observation overhead; this is not a startup
benchmark or a before/after performance claim.
