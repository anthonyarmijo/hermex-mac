# Hermex repository recovery and release preparation goal

Inspect current local and GitHub state before acting. Preserve unfinished work,
complete the release-note guardrails, repair the upstream digest size failure,
correct fork targeting, identify and retire redundant branches/checkouts, review
large local artifacts, and prepare the performance improvements on dev for a
reviewed Mac patch release.

## Execution constraints

- Work from dev on a chore branch; keep master unchanged and buildable.
- Preserve the existing release-guardrails edits and performance roadmap before cleanup.
- Follow AGENTS.md. Verify backups and merged ancestry, then perform the selected
  cleanup without another prompt. Never delete unique work or profiling evidence.
- Use standard-library tooling; introduce no dependencies or server API changes.
- Record benchmark claims as synthetic measurements, not overall app speedups.
- Branch pushes and PR creation/update are included in an approved task. Merges,
  tagging, release dispatch, notarization, and publication need explicit approval,
  which can cover a clearly described sequence once. Do not restart or reconfigure services.

## Deliverables and acceptance

1. A bounded upstream digest that preserves a link to the complete artifact and
   passes small, oversized, Unicode, and Markdown truncation checks.
2. Explicit fork targeting in contributor guidance and automation, with this
   clone's GitHub CLI default set to anthonyarmijo/hermex-mac.
3. Curated release-note validation and reviewed draft highlights for Mac 1.1.1;
   only the Mac marketing version changes.
4. An inventory of unique work and redundant local state, with preservation
   verified before any permitted cleanup and exact outstanding cleanup actions.
5. Passing maintenance checks and a fresh full Mac Catalyst test run for the
   release candidate, or a precise environment blocker without claiming release readiness.
6. Updated local CURRENT.md, a validated local commit, and concrete review and
   publication steps. Do not merge or publish a release without explicit approval.

## Defaults

Use 1.1.1 for the performance-only patch release. Keep raw benchmark reports,
traces, and final test results. Keep the remaining performance roadmap as future
work; image caching, Git diff parsing, and a native UI rewrite are outside this goal.
