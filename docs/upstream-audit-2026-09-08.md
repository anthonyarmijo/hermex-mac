# Upstream audit — September 8, 2026

Snapshot: 2026-09-09T05:04:16.312555+00:00 (September 8 Pacific). Upstream refs can move after this snapshot.

## Hermex client

Latest stable remains [v1.6.0](https://github.com/uzairansaruzi/hermex/releases/tag/v1.6.0),
`2eeb25651e91635ecd01850aaa50bc70af643876`, already integrated in the Mac 1.2.0 candidate.
The inspected client master is `10a3238482cb54175d5b4e0d5f8722ffe93b9268`: eight commits after stable.
The composer fix `9c618bd5d88e8af3495ffd2a652fee77f288903c` was already included.
This selection slice adapts `e84d20ab1d022fcfe2f442456399fbab2d7c54ac`
([#456](https://github.com/uzairansaruzi/hermex/pull/456)), adding Mac pointer dragging,
user-message selection, identity invalidation and Unicode corrections.
The stable pin is retained; the adapted commit is recorded separately.

Six commits remain deliberately deferred:

| Commit | Change | Disposition |
| --- | --- | --- |
| `dd5c3e595ea249711a5eaa432597047dbc8b6ee6` | Open iOS 1.7 release train | Keep Mac and iPhone versioning independent |
| `d21b4d6e483427edc90f0e3e9e0870a4c6b9c4a4` | Provider account limits in Usage | Future feature/contract review |
| `f8a3cffa50d26e24a460c9bc140b652c68a7c9c1` | Reduce math formatting work | Useful next performance slice; not a selection dependency |
| `e49316c1c84861121dbb414d8c75d7c28c5d135e` | Remove obsolete code/tests | Separate cleanup review |
| `9048d5a9b4b181487edfaefb5989d8be1fc6dd91` | Ask Hermex about selected text | New composer/draft behavior, outside this fix |
| `10a3238482cb54175d5b4e0d5f8722ffe93b9268` | Refresh upstream guidance | Review against this fork's Mac release workflow |

[Exact client comparison](https://github.com/uzairansaruzi/hermex/compare/2eeb25651e91635ecd01850aaa50bc70af643876...10a3238482cb54175d5b4e0d5f8722ffe93b9268). Being current with stable does not mean all development commits are included.

## Backend and agent

| Resource | Local checkout | Latest release inspected | Source comparison |
| --- | --- | --- | --- |
| Hermes WebUI | `07118df53c8db0c7fc31e8d244367871526c6347`, describes as `exp-v0.52.215` | Experimental `exp-v0.52.281`; latest non-prerelease `v0.52.113` | 199 commits to `ec63149e81589cd460de4f53825eaa0650670b15` |
| Hermes Agent | `4209d371aa1bb8840ce8447555bdd863a1a96c38` | `v2026.9.7` | Local commit is an ancestor of the release; GitHub comparison reports 6474 commits |

[WebUI comparison](https://github.com/nesquena/hermes-webui/compare/07118df53c8db0c7fc31e8d244367871526c6347...ec63149e81589cd460de4f53825eaa0650670b15) ·
[Experimental release](https://github.com/nesquena/hermes-webui/releases/tag/exp-v0.52.281) ·
[Agent comparison](https://github.com/NousResearch/hermes-agent/compare/4209d371aa1bb8840ce8447555bdd863a1a96c38...v2026.9.7).

The WebUI development branch advanced from 193 to 199 commits ahead, and the
experimental release advanced from .280 to .281 between planning and execution.
This snapshot fixes the comparison target instead of chasing that moving branch.

These are repository/release observations, not a claim that newly checked-out
files are necessarily loaded by a running Python process. The last authenticated
runtime observation remains WebUI `exp-v0.52.215` and agent
`v2026.8.27-432-g4209d371aa`; see the [read-only compatibility report](server-compatibility-2026-09-07.md).
Health remains reachable, but its response does not contain version fields.

The compatibility pin `UPSTREAM_TESTED_SHA` remains
`f1d399b437c1ca7fe4b6d2093aebe334c32f34a3`. Source drift, a healthy endpoint,
and a client selection fix do not satisfy the complete contract gate needed to
advance that pin. No backend checkout, service, credentials, or network settings
were changed. A future server upgrade needs its own backup, compatibility and
rollback plan.
