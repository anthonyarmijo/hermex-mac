# Mac modernization, September 2026

This is an engineering progress record, not a claim that the candidate has shipped.
The selected scope is [the goal prompt](mac-modernization-goal-prompt.md).

## Sources

| Component | Baseline | Status |
| --- | --- | --- |
| Published Mac | mac-v1.1.0, master `aa0e10a` | Published |
| Recovery candidate | `6ceaa5c`, PR #6 | Green; awaiting promotion approval |
| Selected upstream client | v1.6.0, `2eeb25651e91635ecd01850aaa50bc70af643876` | Pinned for this run; integration pending |
| Existing shared client ancestor | `77e8747c3a15ee6bb3d7b40783d9d7fbd6cb28e3` | July 16 baseline |
| Running backend checkout | `07118df5` | Observed locally; authenticated contract checks pending |
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
