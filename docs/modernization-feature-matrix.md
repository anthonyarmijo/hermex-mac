# Mac modernization feature and parity matrix

Snapshot: September 7, 2026. Published Mac 1.1.0 remains unchanged. The reviewed
feature candidate integrates stable upstream Hermex v1.6.0 at
`2eeb25651e91635ecd01850aaa50bc70af643876` plus composer-selection correction
`9c618bd5d88e8af3495ffd2a652fee77f288903c`. A fresh release lookup still identifies
v1.6.0 as upstream's latest published stable release. Post-stable account-limit
Usage work and the 1.7 release-train change are excluded and appear in the
separate client drift report.

| Area | Candidate behavior | Verification / boundary |
| --- | --- | --- |
| Mac window | Explicitly removes the old maximum; retains useful minimum sizes and full-screen support | Signed normal onboarding drag/Fill/full-screen checks passed on the window slice; exact frame/restoration/multiple-display and authenticated final checks pending |
| Connection status | Sidebar and Settings entry; sanitized URL/copy, reachability, auth, versions, latency, refresh, editing/sign-in | Eight focused tests; live health/auth/settings decode; keyboard/VoiceOver/themes/sizing still pending |
| Transcript | Compact thinking/tool rows, finished-turn folding, elapsed-time labels, copy/timestamps, improved scroll preservation | Upstream parser/state/layout suite integrated; normal Mac interaction needs final smoke |
| Composer/drafts | Caret skill completion, skill/file chips, attachment-only sends, durable text/attachment/settings drafts | Gesture correction added; Mac Return/Shift-Return preserved; legacy draft migration/no-resurrection tested |
| Streaming/recovery | Partial-run recovery, late-event guards, session-aware replay; bounded July buffer retained | Full shared suites and repeated byte-identical synthetic replay; no live generated chat in this run |
| Offline cache | Background actor writes and bounded newest-page reads retained; new turn metadata persists | Repeated 50/500/5000 fixtures, two warm-write fetches, main-thread snapshot timing; old text defaults retained for recovery |
| Images | Count/byte caps, ImageIO thumbnails, alpha/orientation, authenticated namespace isolation and cancellation | Ten focused tests, unique-4K retention stress; full original export path remains; normal visual/export smoke pending |
| Workspace/Git | Lazy file tree, source highlighting, unified multi-file review, prepared rows once per response | Actual directory/Git metadata reads; parser/selection/layout/canvas tests; physical mouse/keyboard review pending |
| Tasks/Usage | Agenda, filters/recent/history, model/provider/profile selection, time-window charts | Read responses decode; deterministic mutation/chart tests; no live task execution |
| Kanban | Normal navigation, board/card workflows, bulk actions, dispatcher and per-server restoration | Configuration/board reads decode; full deterministic coverage; no live mutations or worker dispatch |
| Sessions | Attention states, match previews, external-source continuation/import, session-scoped reasoning | Deterministic request/state tests; list/detail/status live reads; live import/history mutation not performed |
| Preferences/models | Hide unused sections, response-speed option, provider-aware model choices | Shared tests and live catalog/settings reads |
| Mac identity | Existing bundle/Keychain/team, dedicated Settings, commands, native file export, manual Mac distribution | Signing verified; platform suite retained; no Keychain/service/network migration |
| iPhone-only capabilities | Live Activities, alternate icons, camera, share extension and haptics remain iPhone-specific | Shared iPhone target builds/tests; not promised as Mac functionality |
| Backend monitoring | Existing tested/triaged pins and separate server watcher retained | Expanded read-only smoke; tested pin deliberately unchanged |
| Client monitoring | Separate bounded weekly client-change digest with integrated/adapted commit pins | Eleven maintenance tests; schedule activates after promotion to default branch |
| Mac idiom experiment | Existing scaled mode retained | Alternate runtime proved but Git/source surface raises unsupported-control exception; experiment rejected for this release |

The full Mac and iPhone suites validate shared code and deterministic contracts;
they do not substitute for the explicitly pending normal-app/manual scenarios.
See modernization-status.md, server-compatibility-2026-09-07.md and the individual
performance reports for counts and limitations.

## Release-note source review

The release notes were curated from the actual `mac-v1.1.0..candidate` first-parent
history and the included upstream commit list, rather than copied from an
automatically generated PR list. Reviewed sources include the fork's cache and
streaming commits/PR5; recovery PR6; window PR9; integration PR11; connection PR13;
watcher PR14; image PR16; Git PR18; idiom PR20; and patch-note PR23.

For upstream user-facing changes, the audit examined PR bodies 344/345 (log rows
and turn folding), 360/405/404 (composer/file references/media), 399 (Git review),
381/375 (Tasks/Usage),298/325 (drafts/recovery),265 (authentication),203 (Kanban),
190/182 (visibility/speed),320/319 (external sessions/reasoning), the v1.6 release
notes and associated issues 376,316,158,189,174,211,180. Their behavior was checked
against the incorporated source and this fork's exclusions. Full source audit
records remain in ignored local evidence; no user server data is included.
