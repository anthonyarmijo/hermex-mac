# Issue Tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for issue operations.

## Repository

- GitHub repo: `anthonyarmijo/hermex-mac`
- Origin: `https://github.com/anthonyarmijo/hermex-mac.git`
- Upstream reference only: `uzairansaruzi/hermex`

GitHub CLI can default to the parent repository in a fork. Set this clone with
`gh repo set-default anthonyarmijo/hermex-mac` and verify with `gh repo view`.
Use explicit `-R anthonyarmijo/hermex-mac` for issue and PR operations. In
GitHub Actions, set `GH_REPO: ${{ github.repository }}` so forks target themselves.

## Conventions

- **Create an issue**: `gh issue create -R anthonyarmijo/hermex-mac --title "..." --body "..."`
- **Read an issue**: `gh issue view -R anthonyarmijo/hermex-mac <number> --comments`
- **List issues**: `gh issue list -R anthonyarmijo/hermex-mac --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`
- **Comment on an issue**: `gh issue comment -R anthonyarmijo/hermex-mac <number> --body "..."`
- **Apply a label**: `gh issue edit -R anthonyarmijo/hermex-mac <number> --add-label "..."`
- **Remove a label**: `gh issue edit -R anthonyarmijo/hermex-mac <number> --remove-label "..."`
- **Close an issue**: `gh issue close -R anthonyarmijo/hermex-mac <number> --comment "..."`

Write multi-line issue bodies and comments to a file and pass `--body-file`.

## Branch and PR Workflow

GitHub Issues are the work queue; pull requests are the review and merge record.

- Pick implementation work from issues labeled `ready-for-agent`, unless the human selects another issue.
- A human-selected `ready-for-agent` issue runs through implementation, validation, branch push, PR creation, and review follow-up without separate permission at each step. For `needs-manual-validation`, open a draft PR and gather the requested manual evidence before marking it ready or merging. See `docs/agents/triage-labels.md`.
- Create a short `issue/<n>-slug` branch for one issue or narrow slice (no-issue branches use `chore/`/`fix/`).
- Commit completed, validated work locally with the matching handoff updates.
- Push feature branches and open/update PRs in this fork as part of the selected task unless the human requested local-only work. Respect an explicit draft-only request. Routine review follow-up and CI checks are included in that authorization.
- Use the PR for review: GitHub/Copilot review, CI, external agent review, and human comments should live there when possible.
- Address PR review comments by triaging them first; do not blindly accept automated review feedback.
- Merge into `dev` or `master` only after validation passes, review feedback is resolved, and the human approves. An approval can cover the stated integration/release sequence; do not ask again for each already-authorized step.
- Keep `master` buildable because it is the protected Mac release-candidate branch.

## Upstream Parity Tracking

- Track upstream parity in the thin, always-current index `docs/agents/feature-gap-index.md` (route group → status + priority + safety + one-line note).
- Create GitHub issues from a `roadmap` row in the index only when a specific gap becomes selected or ready for triage.
- Validate request/response shapes **just-in-time** at implementation time against the pinned upstream copy (not pre-cached in the index); record the validated shape, handler name, and upstream commit in the issue/PR, and reference the archived catalog section when its notes still help.

## Skill Semantics

When a skill says "publish to the issue tracker", create a GitHub issue.

When a skill says "fetch the relevant ticket", run `gh issue view -R anthonyarmijo/hermex-mac <number> --comments`.
