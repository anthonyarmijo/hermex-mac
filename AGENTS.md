# AGENTS.md — working agreement for Hermex

Hermex for Mac is a macOS-focused SwiftUI Mac Catalyst fork of
`uzairansaruzi/hermex` for a self-hosted `hermes-webui` server. The shared iPhone
target remains buildable for upstream compatibility, but this fork's public
distribution is the Mac app. The Xcode target/scheme remains `HermesMobile` and
the product name is `Hermex`. `PROJECT_SPEC.md` is the product/API source of
truth — if a request conflicts with it, stop and ask. Read by every agent
(Codex, Claude Code, …); keep it tool-agnostic.

## Session start & wrap-up
- Read `CURRENT.md` first if it exists — it holds the latest resumable state. It is
  local-only (gitignored), never committed; a fresh clone won't have one.
- Read only the `PROJECT_SPEC.md` sections named in CURRENT.md's **Spec Read** field;
  never the whole ~850-line spec unless told to.
- Active work lives in GitHub Issues. Implement only the issue the human selects, one
  labeled `ready-for-agent`, or one named in CURRENT.md — not every open issue.
- On "wrap up": verify repo/build/test state, overwrite `CURRENT.md` with the new
  state (it stays uncommitted), then commit the code.
  History lives in `git log` and merged PRs; there is no append-only log.

## How work flows
- One issue → one short `issue/<n>-slug` branch → one PR (branches with no issue use
  `chore/` or `fix/`). Issue/triage/domain conventions live in `docs/agents/`.
- `master` is the protected Mac release-candidate branch: keep it buildable and
  never do feature work directly on it.
- A human-selected implementation or cleanup task authorizes the routine work
  needed to finish it: local edits, validation, commits, feature-branch pushes,
  and opening/updating a PR in this fork. Do not ask again at each step. An
  explicit local-only/draft-only request overrides this default. Triage review
  comments, address relevant findings, and follow CI through completion.
- Merging into `dev` or `master` and publishing a release still need explicit
  approval. One approval may cover a clearly described sequence of merges,
  tagging, signing/notarization, and publication; do not request it again for
  each step already included. Ask again only if scope or material risk changes.
- For `needs-manual-validation`, prepare and push a draft PR while automated
  work continues. Keep it draft and do not merge until the requested manual
  checks pass; use one final manual check instead of a gate at every stage.

## Hard rules
1. **Never invent API endpoints or JSON shapes.** Verify in this precedence order:
   (a) `curl` your own running server — final arbiter; (b) the official API docs at
   https://get-hermes.ai/api-docs/ — best for endpoint intent, auth contract, SSE
   event vocabulary, and conventions (no version pin; tracks the latest release);
   (c) the pinned upstream copy at `.codex-tmp/hermes-webui/api/routes.py` — ground
   truth for exact JSON shapes, but may lag the release the docs describe (clone it
   if missing: `git clone https://github.com/nesquena/hermes-webui .codex-tmp/hermes-webui`).
   That upstream copy is read-only — never modify it (refreshing via `git pull` is fine).
2. **No new third-party dependencies** beyond the spec's locked list without approval.
3. **Tolerant decoding:** every `Codable` model uses optionals for fields upstream
   might add/rename. Never crash on unknown fields.
4. **Preserve unique work and live state.** Within an approved cleanup task,
   remove explicitly identified rebuildable outputs and retire merged local or
   remote feature branches/worktrees without another prompt. First verify paths,
   merged ancestry and current remote tips, and preserve any unique or uncommitted
   files in a verified backup. Keep benchmark reports, traces, final test results,
   and signed profiling builds. Never remove an active checkout or use broad
   cleanup commands such as `git clean -fdx` or an unchecked recursive wildcard.
   Deleting unmerged work or user data, force-pushing, changing LaunchAgents,
   restarting services, and changing server/network settings require explicit
   authorization for that operation; routine cleanup authorization does not cover them.
5. **Don't commit broken builds.** If a build or test fails, fix it before writing more code.

## Tooling
- The maintainer works in Agentic Development Environments (Codex, Claude Code), not the Xcode UI — prefer terminal validation;
  ask to open Xcode only when the terminal can't answer.
- Use **XcodeBuildMCP** for simulator build/test/run/log; fall back to raw
  `xcodebuild`/`xcrun simctl` for release/archive or low-level diagnosis. Defaults live
  in `.xcodebuildmcp/config.yaml` (scheme `HermesMobile`, sim **iPhone 17**); if that
  sim is missing, pick a nearby iPhone and say which.
- **Simulator installs must be signed.** Never install a `CODE_SIGNING_ALLOWED=NO`
  build on the simulator for manual testing — that flag is for compile-only checks
  (see `TESTFLIGHT.md`) and strips entitlements, so Keychain writes fail with
  `errSecMissingEntitlement` and login breaks. Put the app on the sim via XcodeBuildMCP
  `build_run_sim` or a plain signed Debug build (no signing-disabling flags), then install/launch.
- Keep validation proportional to the change. During implementation, run focused
  Mac Catalyst tests for the touched behavior. Before asking for review or
  committing a code slice, run the full Mac Catalyst XCTest suite. For shared
  source, target/build-setting, or platform-conditional changes, add focused
  iPhone tests or an iPhone compile check. Reserve the full iPhone XCTest suite
  for upstream Hermex syncs, explicit compatibility work, and periodic CI; do
  not rerun an unchanged green suite in the same slice. Documentation,
  workflow-only, and version-only changes do not require app suites. Keep full
  build logs in files and report summaries or relevant failures so they do not
  consume agent context. Build + launch the signed Mac app when UI changed.

## App identity
Mac bundle ID and Keychain service `com.anthonyarmijo.hermex.mac` · shared iPhone
bundle ID `com.anthonyarmijo.hermex` · Team `8UV3BJB6XS` · Mac releases use the
`mac-vX.Y.Z` tag namespace.

## Mac release (maintainer-only)
The `Mac Release` GitHub Actions workflow accepts an existing tag from current
`master`, validates the Mac suite, signs and notarizes the universal app and DMG,
and creates a draft GitHub Release. Dispatching that workflow, pushing its tag,
or publishing its draft requires explicit human approval, which may authorize
that complete release sequence once the candidate and notes are reviewable.
Existing GitHub environment gates remain in place. Full local and CI instructions
live in `DEVELOPMENT.md`.

Every Mac release must include reviewed, user-facing notes at
`docs/releases/mac-vX.Y.Z.md` before its tag is created. When preparing those
notes, Codex must compare the release candidate with the previous Mac release
tag and inspect the included PR bodies, issues, and commits. Summarize observable
benefits and fixes in plain language, account for every notable user-facing
change, and call out known issues. GitHub's generated PR list is supplemental;
never treat it as the changelog. Show the draft notes to the maintainer for
review before asking permission to tag or dispatch the release workflow.

## Working with the human
- Surface tradeoffs in plain English before non-obvious choices; when in doubt, ask.
- Ask before touching anything under the spec's "Open questions."
- After each slice, report: (1) files changed (2) build/test command run (3) result
  (4) next suggested step — plus a short manual simulator test plan when UI changed.

## Keep this file honest
If something here surprises you or contradicts the project, tell the developer and
**propose** an AGENTS.md edit — don't silently edit it. This file is a Band-Aid for what
can't be fixed in code/tests/tooling; your proposed edits are also a signal of what to fix structurally.
