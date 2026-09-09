# Mac modernization review and release package

Updated September 8, 2026. Engineering changes are committed in the PR stack
below. Repeated normal-app comparisons are recorded with their limitations;
publication and the remaining owner-equipment checks are pending. This document
does not authorize a protected merge, release or live-server change.

Read the curated [Mac 1.1.1 notes](releases/mac-v1.1.1.md) and
[Mac 1.2.0 notes](releases/mac-v1.2.0.md) before approving publication. The
[feature matrix](modernization-feature-matrix.md),
[integrated performance report](performance/INTEGRATED_MODERNIZATION_2026-09-07.md)
[normal app validation](performance/NORMAL_APP_VALIDATION_2026-09-07.md),
[matched normal-app comparison](performance/NORMAL_APP_COMPARISON_2026-09-08.md)
and [server compatibility report](server-compatibility-2026-09-07.md) describe
what was verified and what remains uncertain.

## Exact starting revisions

Protected branches remain unchanged: master is
`aa0e10a9e9c145c0d5c86e010b449bd03dc105d5` (published Mac 1.1.0), and dev is
`883236f0c04c0af8bc1429ec0e11ce7ce300d3ae`.

| Order | PR / purpose | Reviewed feature head |
| --- | --- | --- |
| Patch 1 | [#6 recovery and July performance release preparation](https://github.com/anthonyarmijo/hermex-mac/pull/6) | `6ceaa5c09f7bd066624eee343dfb00f98cfa6c1b` |
| Patch 2 | [#9 expandable Mac windows](https://github.com/anthonyarmijo/hermex-mac/pull/9) | `ae1467d5c62430bb7db64b53172f9f66d8865a3b` |
| Patch 3 | [#23 corrective release notes](https://github.com/anthonyarmijo/hermex-mac/pull/23) | `19e659ae4f9c837e2f654fa59b723bacda9fc105` |
| Feature 1 | [#11 stable upstream integration](https://github.com/anthonyarmijo/hermex-mac/pull/11) | `953269ce03989bd559f3c4a745da3273c758144a` |
| Feature 2 | [#13 connection status](https://github.com/anthonyarmijo/hermex-mac/pull/13) | `ca8a4ce79d0217509ad266709f4c8c072fa2ba43` |
| Feature 3 | [#14 client drift watcher](https://github.com/anthonyarmijo/hermex-mac/pull/14) | `6b93aa5c9496fa8a4f2d27a584b3097a31a90ac0` |
| Feature 4 | [#16 bounded images](https://github.com/anthonyarmijo/hermex-mac/pull/16) | `847b6922b30e2c8a72c79fbd778d0b8402d83049` |
| Feature 5 | [#18 Git diff preparation](https://github.com/anthonyarmijo/hermex-mac/pull/18) | `3316a0caeff294cf31af4bd80f6c6d1693325433` |
| Feature 6 | [#20 Catalyst experiment evidence](https://github.com/anthonyarmijo/hermex-mac/pull/20) | `5ae54927afefa9ad6b14f185b2d6f4bac4bee7c5` |
| Feature 7 | [#24 integrated validation and release package](https://github.com/anthonyarmijo/hermex-mac/pull/24) | `2a0bb38504c01278937d48b3c76e972fcfc444b4` |
| Feature 8 | Markdown image correction and normal-app validation (#25) | `issue/25-bounded-markdown-images`; exact final head is recorded in its PR body |

The final row avoids putting a commit's own hash inside its content. Verify the
PR's current head against the recorded SHA before executing this sequence.
All earlier PR checks are green at these heads. The final PR records its own
CI outcome. Draft UI PRs remain draft until the applicable checks below pass.

## Release choice after the baseline hang

Prefer the complete 1.2.0 feature candidate for the next release. The separate
1.1.1 patch remains available for review, but its ancestor reproduced an
image-scroll hang and the exact patch binary has not passed that reproduction.
Do not assume the window correction resolves that separate behavior. Publishing
the patch first should wait for that check or an explicit acceptance of this
known risk. Keeping the small patch reviewable does not require publishing it.

For a single 1.2.0 release, merge the reviewed #6, #9 and #23 changes into dev,
then the feature rows in order, following checks at each changed base. Skip the
intermediate dev-to-master promotion, 1.1.1 tag and publication. Proceed directly
to the validated 1.2.0 promotion and release described in step 5 below. The two
release sequence is retained as an optional alternative, subject to the patch
check and owner choice. Neither sequence is authorized by this document.

## One promotion and publication sequence

After the owner has reviewed the notes and explicitly approved this sequence:

1. Recheck remote tips and PR heads. Merge #6 into dev, retarget #9 to dev and
   merge it after its final window checks, then retarget #23 to dev and merge it.
   Preserve ancestry with merge commits so downstream stacked changes remain
   reviewable; do not force-push or silently substitute different feature heads.
2. Open the dev-to-master corrective promotion PR, follow its checks to green,
   and merge it. Verify the exact resulting master commit contains the reviewed
   patch changes, Mac version 1.1.1 and its notes. Record that commit before
   creating the previously absent `mac-v1.1.1` tag on it.
3. Push that tag and dispatch the existing Mac Release workflow. Honor existing
   environment approvals. Verify the universal app and DMG, signature,
   notarization and version; inspect the draft release and its curated notes.
   Complete the second-Mac installation smoke, then publish the draft if the
   approval includes publication and the required checks pass.
4. Retarget the feature PRs to dev and merge them in the table's order, preserving
   ancestry and following checks at each changed base. The final validation
   branch carries the same patch notes as #23, allowing both release histories
   to remain coherent. Address any actual conflict and revalidate its effects.
5. Open and validate the feature dev-to-master promotion PR. After all applicable
   manual checks pass, merge it, verify Mac version 1.2.0 and the reviewed notes,
   and record the exact resulting master commit. Create `mac-v1.2.0` on that
   commit, dispatch Mac Release, verify signed/notarized artifacts, inspect the
   draft, complete its installation smoke and publish within the same approved
   scope. The shared iPhone version remains independently 1.6.0.

Promotion commits do not yet exist, so their SHAs cannot honestly be supplied
in advance. They must derive only from these approved heads and validated
promotion merges. Stop for a material scope change, failed required validation
or an unexpected remote tip. Routine retargeting, checks and already-approved
steps do not need repeated informal approvals. Neither release upgrades the
backend or changes the user's network, LaunchAgents or server configuration.

## Consolidated final manual check

The owner unlocked the desktop and signed in. Authenticated main-window drag,
Fill, tiling, full-screen, large-window/draft restoration, response text selection,
connection display/copy/refresh/edit, keyboard navigation and light/dark checks
passed. Controlled fixture error states, 24-image scrolling, original export and
Git collapse/dismiss/reopen and selected line insertion into the composer also
passed. Original server reachability and restored sign-in were verified again
on September 8; see the normal-app report for limits.

The remaining owner checklist is:

- Move between physical displays with different sizes/scales, disconnect one,
  and confirm no stale cap or stranded restored window. Exact native frame/desktop
  point telemetry is not established by rescaled automation captures.
- Check spoken VoiceOver output. Labels and keyboard actions were inspected,
  but a spoken readout was not verified.
- Install the signed/notarized candidate on a second Mac, connect using the
  reachable server address and authenticate while the server Mac is awake.
  Localhost refers to the machine running the client.

Normal transcript and image-scroll Time Profiler captures exist. Four matched
fresh-process samples per version now measure process exec through initial frame:
339.99 ms median before, 352.58 ms after, with warm disk caches. Warm reopen
and controlled resize workflows have now completed four trials per version;
their durations include automation overhead. The baseline image workload hung
twice, while the corrected candidate completed four cycles. A failed candidate
frame capture leaves no paired FPS or peak-memory result. Do not present these
limits as a universal speedup.
The production image-input correction passed full Mac tests in a separate test
identity, iPhone compilation and normal image-width verification. The corrected
normal app was then built with the ordinary Mac identity, signed and launched;
it restored the existing chat and freshly verified Reachable/Signed in. The
resize trace recorded no detected stalls over 250 ms for either benchmark app.

Actual generation or session/task/Kanban mutations need a specifically approved
disposable-data smoke as described in the compatibility report. They have not
been performed on existing user sessions. The backend tested pin remains
unchanged until its complete contract gate is satisfied.

## Evidence and remaining decisions

Latest full signed Mac suite: 2,370 total, five expected skips, zero failures.
The integrated full iPhone suite had 2,365 total with five expected skips and zero
failures; the subsequent shared image correction passed 26 focused iPhone tests. The explicit live test decoded 27 production
read responses. Eleven maintenance checks pass. Release notes validate and the
signed Mac candidate passes strict signature verification.

Git preparation improves the matched incremental fixture from 36 parses to
eight, with median time 1,734 to 391 ms. The image cache has a measured retention
bound. The integrated candidate also has measured costs: roughly 7–8% slower
large background cache writes, about 1.5 ms higher hosted first-frame median
with twice as many visible rows, and about 69 ms higher short synthetic stream
completion. The report preserves these concerns; it does not claim every path
got faster. The alternate Mac idiom is rejected because a real unsupported
control exception occurs in the review surface. No native rewrite is proposed.

Keep the unmerged branches, baseline and patch worktrees, backup archives,
signed profiling builds, final results and traces. Retire feature branches only
after verifying they are merged and contain no unique work. No additional broad
cleanup is needed before review.
