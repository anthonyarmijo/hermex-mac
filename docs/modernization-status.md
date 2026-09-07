# Mac modernization, September 2026

This is an engineering progress record, not a claim that the candidate has shipped.
The selected scope is [the goal prompt](mac-modernization-goal-prompt.md).

## Sources

| Component | Baseline | Status |
| --- | --- | --- |
| Published Mac | mac-v1.1.0, master `aa0e10a` | Published |
| Recovery candidate | `6ceaa5c`, PR #6 | Green; awaiting promotion approval |
| Selected upstream client | v1.6.0, `2eeb25651e91635ecd01850aaa50bc70af643876` | Integrated locally; final verification in progress |
| Existing shared client ancestor | `77e8747c3a15ee6bb3d7b40783d9d7fbd6cb28e3` | July 16 baseline |
| Running backend checkout | `07118df5` | Authenticated health/auth/settings checked; wider contracts pending |
| Validated backend pin | `f1d399b437c1ca7fe4b6d2093aebe334c32f34a3` | Unchanged; not the running backend version |

## Selected work

- #7: independently reviewable Mac window correction, stacked on recovery PR #6.
- #8: stable client integration, connection diagnostics, client drift watcher,
  remaining image/Git/idiom performance work, compatibility and release preparation.

The upstream target is fixed. Later commits require an explicit applicability
assessment rather than silently changing that target. Mac identity, platform
boundaries, background cache writes, bounded streaming/replay handling, existing
maintenance workflows and contractual documentation must survive the integration.

## Verification boundaries

The current machine has one connected display. A physical second-display move or
disconnect and a signed release installation on another Mac require owner checks.
The normal app currently presents an expired session; authenticated interaction
checks must not be claimed from onboarding or the Streaming Lab. No credentials,
live backend configuration or network settings have been changed.

Merges into dev/master and release publication remain separately authorized
operations. Engineering continues on feature branches before that final approval.

## Window correction evidence (#7)

The normal signed app reproduced the restriction on the connected display
(2560 × 1920 pixels, configured as 1280 × 960 desktop points). Its pre-fix
maximized capture was 966 × 719. These are capture dimensions, not an exact
AppKit frame measurement; computer-use captures rescale larger windows.

Removing the explicit maximum alone was rejected: UIKit retained a finite
initial maximum and native Fill remained restricted. The final policy uses
`CGFloat.greatestFiniteMagnitude` on each dimension to express no application
upper bound through `UISceneSizeRestrictions`. It preserves the existing
minimum sizes, default sizes, full-screen support, and system restoration.
No screen-derived size or scaling multiplier remains.

The signed normal app was launched after rebuilding (without a lab argument).
Native Fill and corner dragging expanded beyond the old limit; shrinking and
expanding, entering full screen and returning to the desktop all preserved a
usable onboarding form without a snap-back. The large-window capture was
1131 × 768 after capture scaling. Exact effectiveGeometry/desktop frame values,
authenticated chat/Settings interaction, tiling on a sufficiently wide display,
and physical display changes still require additional checks before declaring
all milestone acceptance criteria verified.

Validation on Xcode 26.6:

- Focused platform regression passed.
- Full signed Mac Catalyst suite: 1518 executed, two expected skips, zero failures.
- iPhone simulator compile passed; unsigned compile output was not launched.
- The regression applies both scene minima repeatedly to real scene restrictions
  with simulated stale maxima and checks that the cap is removed.

Full logs/results are retained locally in `.codex-tmp/mac-modernization/`:
`window-full.log`, `WindowFull.xcresult`, and `window-iphone-build.log`.

## Stable client integration (#8)

The local merge includes the applicable Swift client functionality through
v1.6.0: streaming/recovery and draft fixes; provider identity; log-row transcript
and turn folding; composer chips and caret completion; attachment-only sends;
lazy workspace tree, source and Git review surfaces; image previews; Tasks
agenda/history; Usage charts; session attention/search/continuation; settings
visibility controls; and the completed Kanban workflow.

The deliberately included post-stable correction is upstream
`9c618bd5d88e8af3495ffd2a652fee77f288903c` (#450), applied only to
ComposerChipTextView and its gesture tests. It prevents chip recognition from
interfering with ordinary caret placement/selection. The stable target remains
v1.6.0; no other later client commits are implied.

Deliberate adaptations/exclusions:

- Preserve Mac app/Keychain/signing identity, dedicated Settings, commands,
  interface scaling, file export, pointer affordances and platform capabilities.
  Live Activities, alternate icons, camera and iOS share surfaces stay unavailable
  on Mac while their shared iPhone implementations remain buildable.
- Preserve this fork's AGENTS, review rules, product/API specification, development
  and release documentation, backend contract checklist/pins and backend watcher.
  Upstream's removal/rewrite of those policies is not imported into this fork.
- Preserve platform-specific onboarding/server instructions already hardened here.
  This excludes upstream's exact iPhone-only setup prose, including its request to
  return the server password; no live setup action is performed by this merge.
- Keep the background cache writer and bounded newest-page reader instead of
  upstream's synchronous writes. Bring new turn speed/duration metadata through
  the background snapshot, storage and reload path. Keep the measured replay
  buffer, lazy transcript rows and media-parser fast path; expand the latter to
  recognize upstream's Markdown images and bare file links.
- Use upstream's durable draft store with an atomic migration marker for this
  fork's older text drafts. Retain the old defaults for recovery but do not
  reimport them after a successful send/clear. Newer durable drafts take priority.
- Mac feature candidate is 1.2.0; the shared iPhone train is 1.6. Public distribution
  and release approval remain Mac-specific.

First combined suite: 2336 Mac tests, four skips, 24 failures concentrated in
media fast-path integration and an obsolete source assertion. After correcting
those paths and adding draft migration, 2337 Mac tests passed, four skips, zero
failures. The preserved 50,000-character stream fixture scanned/copied 321,426
characters, matching the optimized July result; this is a synthetic regression
measurement, not a complete UI benchmark. Final validation including the post-stable gesture fix passed on both Mac and
iPhone: 2341 tests each, four expected skips and zero failures. Maintenance
regressions also pass (eight tests). The normal signed integrated UI launch
is pending because the desktop locked; the owner has been asked to unlock it.

Authenticated read-only checks on September 7 returned HTTP 200 for auth/status
and settings: WebUI `exp-v0.52.215`, agent `v2026.8.27-432-g4209d371aa`, password
auth enabled and signed-in status true. Credentials and cookies were held only
in the check process and were not printed or committed. The existing app's
separate expired session was not reset. No server or validated pin was updated.
