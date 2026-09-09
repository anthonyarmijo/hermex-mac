<!-- Thanks for contributing! Please read CONTRIBUTING.md before opening a PR. -->

## Linked issue

<!-- Every PR should close an issue, e.g. "Fixes #123". If there is no issue yet, open one first. -->

Fixes #

## What changed

<!-- A short, plain-English summary of the change and why it's the right fix. -->

## Release note

<!--
Write one short, user-facing bullet for the next Mac release. Describe the
benefit or behavior, not the implementation. If this should not appear in the
release notes, write: None — internal change.
-->

## How it was tested

<!-- e.g. full Mac Catalyst XCTest suite (command + result), signed Mac UI checks.
Docs/workflow/version-only changes need no app suites. Upstream integrations
need an iPhone compile check; full iPhone tests are explicit opt-in only. -->

## Checklist

- [ ] Full Mac Catalyst tests pass for app changes; otherwise explain why app tests are not needed
- [ ] Signed Mac UI checks pass when interactions or layout changed (or not applicable)
- [ ] Upstream integration has an iPhone compile check (`upstream-integration` label); full iPhone tests only if explicitly requested (`full-iphone-tests` label), or not applicable
- [ ] New/changed `Codable` models decode tolerantly (optionals for fields the server might add or rename)
- [ ] No new third-party dependencies (the list in `AGENTS.md` is locked)
- [ ] No invented API endpoints or JSON shapes (verified against upstream source or a running server)
- [ ] The release note above is user-facing, or explicitly marked `None — internal change`
