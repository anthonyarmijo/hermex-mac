# Catalyst interface-mode experiment — September 7, 2026

Issue #19, identical source based on 3316a0c plus two runtime/construction tests.
Decision: **retain the existing iPad idiom for this release**. The alternate Mac
idiom is proven at runtime but raises an exception when constructing Hermex's
Git/source review surface. No experimental target setting is committed.

## Setting and runtime evidence

Apple documents the two modes and their different control metrics in
[Choosing a user interface idiom](https://developer.apple.com/documentation/uikit/choosing-a-user-interface-idiom-for-your-mac-app).
Its [build-settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)
identifies `TARGETED_DEVICE_FAMILY=2` as scaled iPad Catalyst and `6` as Optimize
for Mac; the build system produces UIDeviceFamily from that setting. These
primary sources were checked September 7, 2026.

The existing target declares `1,2`, which processes to `[2]` for Catalyst.
The alternate build overrides only `TARGETED_DEVICE_FAMILY=6` on the build
command line, processing to `[6]`. Both use Xcode 26.6, signed Debug, arm64,
code coverage disabled, identical source/tests and the same Mac M4/24 GB on
macOS 26.6.2 (25G83). `SUPPORTS_MACCATALYST` alone was not used to infer the mode.

| Runtime probe | Control | Alternate |
| --- | --- | --- |
| Processed family | [2] | [6] |
| Device and connected-scene idiom | pad (1) | mac (5) |
| Preferred body font points | 17 | 13 |
| Review surface construction | Pass | Unsupported-control exception |

The new tests compare both actual idioms with processed metadata and construct
the real ReviewDiffSurfaceView. This catches the alternate mode's exception:
`UIRefreshControl` is unsupported in the Mac idiom. The system suggests a Refresh
menu item with Command-R. The construction fails before ordinary Git review
interaction can be assessed. This is an observed blocker, not a hypothetical
compatibility concern or a compile failure.

## Measurements and limitations

After both builds completed, the same selected synthetic tests ran sequentially
again. Prepared eight-file Git work used one warmup and five samples: control
median/p95 394.744/447.096 ms, alternate 397.498/426.381 ms. The four-image fixture
retained 25,198,592 decoded bytes in both; cold median/p95 14.118/90.725 ms versus
15.345/96.390 ms, warm 0.110/3.714 ms versus 0.110/4.511 ms. These do not establish
a material algorithmic speed benefit from changing the platform mode.

The test host's reported display changed between runs (3440×1440 at scale1,
then 1600×1200 at scale2). Scene sizes also differed with the idiom's coordinate
metrics. Therefore these runs are **not a controlled visual/rendering A/B**.
No first-frame, scrolling-hitch, CPU/energy, normal-window geometry, screenshots
or accessibility improvement is claimed from them.

| Compatibility area | Evidence / status |
| --- | --- |
| Runtime selection, signing, scene restriction policy | Automated probes pass in both modes |
| Git/source review surface | Mac-idiom construction throws; release blocker |
| Interface metrics | Body-font/scene metrics differ; full layout review pending |
| Composer chips, text wrappers, Markdown/math, media | Inventory complete; normal interaction comparison pending |
| Menus, sheets, Settings, onboarding, file export | Existing standard-mode suite; alternate manual matrix blocked |
| Keyboard, VoiceOver, themes, Reduce Motion, external displays | Pending unlocked desktop and stable display setup |
| iPhone | No persistent target change; focused platform checks retained |

Mac-specific scale/environment preferences and UIKit wrappers remain unchanged.
No attempt was made to compensate for the alternate idiom with new scaling or
to fix several screens inside this spike. A follow-up could replace/guard the
review surface's pull-to-refresh control and then run a stable-display UI and
profiling pass. That is one bounded compatibility change plus a wider validation
pass; the current evidence does not justify adoption or a native rewrite.

## Retained evidence

The initial control probe had an incorrect test initializer; it was fixed before
the passing control run. The final alternate code builds and signs successfully;
its failure is the runtime compatibility test described above. The default
candidate remains green; the failed experiment is retained as evidence.

Both signed app bundles are preserved under
`.codex-tmp/mac-modernization/idiom-preserved/{control,alternate}/Hermex.app`.
Build settings, full logs and result bundles are retained as IdiomControl2,
IdiomAlternate, IdiomControlMeasured and IdiomAlternateMeasured. Final normal
Mac/iPhone suite results are recorded in modernization-status.md.

The Mac remained locked through the experiment; CUA could not obtain the desktop.
The owner was asked once to unlock it. The missing manual matrix is an external
validation dependency; it has not been silently marked passed.
