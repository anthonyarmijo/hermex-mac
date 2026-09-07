# Hermex Mac modernization goal prompt

Paste the prompt below into a new Goal run from this repository. Creating this
document does not start that run. Use one overarching goal with sequential,
reviewable milestones; do not create competing nested goals.

---

## Goal

Bring Hermex for Mac up to a substantially better, current, release-ready state:
fix the window-size restriction, integrate applicable upstream Hermex updates,
add a useful connection-status screen, improve remaining measured performance
hotspots, and prepare a coherent release candidate. Complete the engineering
and verification work rather than stopping at an audit, a list of suggestions,
or one easy fix. Keep the existing Mac experience, signing identity, server
credentials, data, and shared iPhone compatibility intact.

Work in `/Users/anthonyarmijo/dev/apps/personal/hermex-mac`.

## Grounding and working agreement

1. Read `AGENTS.md` and `CURRENT.md` first. This goal additionally authorizes
   targeted spec reading for sections 3 (architecture), 6.1 (auth/health), 6.6
   (server panels), the onboarding/offline-cache/settings phases, section 9
   (server-hosting docs), and the relevant platform/UI sections identified from
   the heading index. Read only what each milestone needs and record those
   selections in CURRENT.md's Spec Read field. Respect the product/API source
   of truth; ask about an actual conflict or an Open questions decision rather
   than guessing. Do not read the entire spec by default.
2. Inspect local changes, branches, worktrees, GitHub PRs, CI, release tags,
   upstream refs, and available build tools. Treat the snapshot below as a
   starting point, not current truth. Prefer graph tools for code discovery.
3. This prompt selects the milestones below as implementation scope. Track
   them with narrowly scoped issues and branches/PRs using repo conventions.
   Do not implement unrelated open issues or expand into a native UI rewrite.
4. A selected task includes routine edits, tests, commits, feature-branch
   pushes, PR creation/update, review follow-up, and verified cleanup. Follow
   current AGENTS.md rather than older local-only instructions embedded in
   historical performance prompts. Preserve explicit user overrides.
5. Never work directly on protected master. If the recovery PR is still
   unmerged, continue from its verified candidate using stacked feature
   branches/PRs instead of stopping all work for an early integration gate.
   Local upstream integration into an isolated feature branch is implementation
   work; promotion into dev/master remains a separately approved operation.
6. Do not ask for permission at every milestone. Prepare a concrete integration
   and release sequence for one approval once changes, notes, and validation
   are reviewable. Honor any approval already given for those exact actions.
   Do not merge dev/master, tag, notarize, dispatch or publish a release without
   that authorization. Do not bypass GitHub environment protections.
7. Do not restart or upgrade the running backend, change network/LaunchAgent
   settings, force-push, delete unique data, or add dependencies without the
   operation-specific approval required by AGENTS.md. Progress on independent
   engineering work while any such decision is pending.

## Starting evidence to revalidate

- September 7, 2026: recovery PR #6 targets dev, with head `6ceaa5c` and green
  maintenance, Mac Catalyst, iPhone compatibility, and CI Gate checks.
- The recovery candidate prepares Mac 1.1.1. Published Mac 1.1.0/master did not
  yet include dev's July cache-write and streaming optimizations.
- The local signed Mac suite passed with 1,519 tests, two expected skips, and
  zero failures. The iPhone compile check also passed. These are historical
  results, not substitutes for validating new changes.
- The fork last shared upstream client commit `77e8747` on July 16. The observed
  upstream client master had 111 commits absent from this fork; upstream 1.6.0
  was released September 6. Mac/client version numbers are independent.
- The Mac mini's backend checkout was at August 13 commit `07118df5`, 93 commits
  behind the observed backend master. The running backend, tested contract pin,
  and upstream client revision are separate facts and must remain distinct.
- Existing window code in `HermesMobile/HermesMobileApp.swift` sets a maximum
  from `windowScene.screen.bounds.size`. The user confirmed that the outer
  window itself stops growing, not merely that its content stays narrow.
- Existing performance evidence and the remaining program are under
  `docs/performance/` and `docs/performance-optimization-goal-prompts.md`.
- Recovery archives and original profiling evidence remain under the ignored
  `.codex-tmp/` directory. Do not delete them to simplify this work.
- Xcode was installed at `/Applications/Xcode.app`, while the machine-wide
  developer path pointed to Command Line Tools. Prefer a per-command
  `DEVELOPER_DIR` override over changing machine-wide settings.

## Milestone 1 — Make the Mac window freely expandable

Reproduce the restriction in a signed build of the normal main app window and
record its actual maximum size against the display's usable desktop area. The
Streaming Lab bypasses the main sizing modifier and cannot prove this fix.

Inspect the scene size restrictions, effective window geometry, Catalyst
coordinate scaling, SwiftUI scene modifiers, and display-change behavior. Fix
the actual limiting mechanism using supported APIs. Do not substitute a larger
arbitrary hardcoded cap, a magic 77% correction, or a wholesale change to
Optimize Interface for Mac as an unmeasured workaround.

Acceptance:

- Dragging the main window can fill the display's usable desktop area.
- Standard maximize, tiling where the existing minimum permits it, and full
  screen work without clipping, snapping back, or an artificial upper limit.
- Moving between displays with different sizes/scaling does not retain the
  smaller display's cap. Restored large windows remain usable after relaunch;
  disconnecting a display does not leave the app stranded off screen.
- Preserve sensible existing minimum/default sizes and normal macOS restoration.
  Do not force maximization or full screen at launch.
- Sidebar, composer, scrolling, text selection, and Settings remain usable at
  small and large sizes. Do not redesign chat text width to solve this outer
  window problem. Preserve iPhone behavior.
- Replace tests that merely encode the old screen-derived cap with regression
  coverage for the corrected policy, and provide signed live-window evidence.

Keep this independently reviewable and suitable for a small corrective release
even if the larger upstream integration takes longer.

## Milestone 2 — Bring the client forward from upstream

Refresh upstream metadata and select the latest stable original Hermex release
available when the run starts. Record its tag and peeled commit SHA and keep
that target fixed for this run; do not chase a moving master indefinitely.
Assess later critical fixes separately and document any deliberately included
commits. The observed 1.6.0 release is a starting candidate, not a permanent pin.

Create a compatibility inventory against the fork and integrate applicable
shared-client changes on an isolated branch. Aim for the selected stable
release's applicable functionality and correctness fixes, not a handful of
cherry-picks described as a complete sync. Record every deliberate exclusion,
its Mac/product reason, and any remaining user-visible gap.

Prioritize streaming/reconnect recovery, draft preservation, authentication,
scroll behavior, and session correctness before large UI changes. Then bring
forward applicable composer, workspace/file viewing, Git review, Tasks/Usage,
and settings improvements. Reuse upstream implementations when appropriate.

Preserve the Mac bundle ID, Keychain service, team, signing/release workflow,
dedicated settings window, keyboard/menu behavior, and platform capability
boundaries. Resolve conflicts deliberately. Preserve the guarantees and
measured benefits of the fork's background cache writer, bounded streaming
buffer, replay deduplication, Unicode handling, and Markdown fast paths;
equivalent improved implementations are acceptable when verified.

Add a bounded weekly upstream-client digest alongside the existing backend
watcher. Reuse the maintenance infrastructure, but distinguish client and
backend source names, baselines, issues, and report artifacts. Keep one standing
issue per source, link complete reports, and handle oversized/Unicode content.
The watcher reports drift; it must not auto-merge or upgrade a live server.

Deliver a source/version matrix distinguishing the Mac release, integrated
upstream client revision, running backend version, and validated backend pin.
Only advance a tested pin after its required contract checks actually pass.

## Milestone 3 — Add the Connection status screen

Provide an obvious entry from Settings and a discoverable status affordance in
the main Mac interface. Reuse an applicable upstream status implementation if
the sync supplies one. Avoid building a duplicate subsystem. Integrate with
the existing server registry, authentication, networking, and design patterns.

For the selected server, show:

- Its display name and configured base URL, with a copy action. Sanitize any
  credentials or sensitive query parameters; never expose passwords, cookies,
  custom auth headers, or tokens in the screen or diagnostics.
- Reachability: not configured, checking, reachable, or unreachable, with last
  check time and measured response latency when available.
- Authentication separately from reachability. A successful health response
  must not imply the user is signed in or every required API works.
- Hermes WebUI server version and agent version when the actual API supplies
  them. Missing/older-server fields display as unavailable; they do not crash
  decoding or incorrectly mark a reachable server offline.
- A clear Refresh/Check connection action and useful error explanations for
  DNS/network failure, timeout, TLS failure, authentication required, or an
  unexpected/incompatible response. Route sign-in and editing through existing
  flows rather than silently resetting credentials.
- A concise explanation that Hermex is a client and the server machine must be
  awake/reachable. For localhost/loopback URLs, explain that the address refers
  to the Mac currently running Hermex; another Mac needs a reachable server URL.

Use only verified read endpoints and existing authentication/header handling.
Follow AGENTS.md's live-server/docs/pinned-source verification order. The
existing documentation identifies health and authenticated settings reads;
verify their actual payloads before relying on fields or adding models.

Check when the screen appears and when explicitly refreshed. Use bounded
requests, cancellation, and coalescing; do not add perpetual background polling.
Cancel/invalidate work on server changes, and never let a late response from
server A update server B's status. Any cached success/version data must be
server-scoped and visibly marked stale after a failed check.

Test unconfigured and signed-out states, reachable/authenticated and
reachable/auth-required states, unavailable version fields, offline/timeout/TLS
errors, refresh overlap, server switching during a request, stale data, and
secret redaction. Verify keyboard navigation, VoiceOver labels, light/dark
appearance, and small/large windows. Do not hardcode the maintainer's hostname
or Tailscale IP into product code or public documentation.

## Milestone 4 — Finish the highest-value performance work

Use the existing program as technical guidance, first checking what upstream
has already improved. Do not reimplement solved work or repeat rejected
experiments without new evidence.

1. Bound decoded transcript image memory and downsample images to useful display
   sizes. Preserve media fidelity, server isolation, authenticated loading,
   cancellation, cache eviction, and warm-cache responsiveness.
2. Parse each loaded Git diff once outside SwiftUI body evaluation. Avoid
   unnecessary re-parsing and main-thread work; preserve binary/oversized-diff
   behavior, line numbering, content accuracy, and navigation.
3. Run an isolated Optimize Interface for Mac experiment after the core fixes.
   Measure layout, controls, rendering, and input behavior. Retain it only if
   its benefits survive regression checks; otherwise document and discard the
   experiment's changes. Do not bundle it into the window fix by assumption.
4. Re-measure the complete integrated candidate: cold/warm startup, opening
   long cached transcripts, large cache writes, long streaming replies,
   image-heavy scrolling, Git diffs, and responsiveness during resizing.

Use matched fixtures, build settings, hardware, and repeated samples. Report
medians/tails and memory/CPU only where actually measured. Compare against the
pre-change fork and relevant upstream behavior; distinguish synthetic results
from real interface smoothness. Accept an unsuccessful experiment with sound
evidence, but do not present missing measurements as a successful optimization.

## Milestone 5 — Validate server compatibility and prepare the release

Check the candidate against the currently running backend without changing the
server or real user sessions. Use verified read-only authenticated flows where
available and deterministic fixtures for mutating behavior. Actual chat
generation, destructive calls, or backend upgrades need the applicable explicit
authorization; prepare a specific disposable-data smoke plan if required.

If newer client functionality needs a newer backend, identify the exact version
requirement and prepare a reviewed backup, upgrade, validation, and rollback
plan. A health response alone does not prove compatibility. Do not claim that
updating client code has also updated the Mac mini's backend.

Keep the window/performance corrective release separable from the larger
upstream modernization release. Verify tags before assigning versions; use
1.1.1 for the already-prepared patch only if still appropriate/unpublished, and
1.2.0 for the subsequent feature-bearing Mac release if available. Use the Mac
tag namespace and do not renumber the independent iPhone release train.

Prepare curated release notes from the actual diff since the previous Mac tag,
including status-screen benefits, resizing, upstream changes, measured
performance improvements, server requirements, and known limitations. Do not
promise features that were excluded or not validated.

Present one concrete approval package identifying PRs, exact revisions,
promotion order, versions/tags, and the intended signing/notarization/publication
steps. Execute only the authorized portion. Existing GitHub environment gates
and requested owner checks still apply; do not turn them into repeated informal
permission questions for steps already approved.

## Validation and completion

- Keep tests proportional during implementation. Before submitting each code
  slice, run the required full Mac Catalyst suite. Add iPhone compile/focused
  checks for shared/platform changes; the upstream sync requires the full
  iPhone suite. Do not repeatedly rerun an unchanged green suite in one slice.
- Build and launch signed Mac UI changes. Never install or launch an unsigned
  simulator build for manual testing. Keep full logs/results in ignored files.
- Exercise the normal Mac window on the available display configurations and
  the status screen with deterministic error states. Clearly identify any
  physical-display or remote-Mac checks that remain for the owner.
- Address relevant review findings and follow PR CI to completion. Preserve
  unrelated work and original benchmark evidence. Retire only verified merged
  branches, redundant worktrees, and identified reproducible artifacts.
- Maintain CURRENT.md as the resumable state and commit verified slices. Track
  each milestone as implemented/verified, evidence-based rejected experiment,
  or blocked with a specific missing dependency; do not quietly drop work.
- At the end, provide PRs/commits, a feature/parity matrix, window and connection
  evidence, before/after performance results, the server compatibility matrix,
  release notes, and the exact remaining approval/manual actions.
- Do not mark the whole goal complete merely because the window fix ships or
  one difficult milestone is deferred. Engineering completion requires all
  required features, applicable upstream integration, performance investigations,
  and validation deliverables above. An experimental optimization may be
  rejected with evidence; an unimplemented required feature may not.
- Release preparation is complete when the reviewed candidate and approval
  package are ready. Public distribution and live-server upgrades are separate
  authorized operations; report them as pending until actually performed.

## Out of scope

No native AppKit/SwiftUI rewrite, hosted backend service, automatic production
server updates, public network exposure, unrelated feature development, or new
third-party dependencies without a separate explicit decision. Keep this goal
focused on a dependable Mac client that uses the user's display, explains its
connection, benefits from current upstream work, and has measured performance.
