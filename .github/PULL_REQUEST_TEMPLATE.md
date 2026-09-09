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

<!-- e.g. full XCTest suite (command + result), manual simulator steps, screenshots for UI changes. -->

## Checklist

- [ ] The full test suite passes locally (`xcodebuild test -project HermesMobile.xcodeproj -scheme HermesMobile -destination 'platform=iOS Simulator,name=iPhone 17'`)
- [ ] New/changed `Codable` models decode tolerantly (optionals for fields the server might add or rename)
- [ ] No new third-party dependencies (the list in `PROJECT_SPEC.md` is locked)
- [ ] No invented API endpoints or JSON shapes (verified against upstream source or a running server)
- [ ] The release note above is user-facing, or explicitly marked `None — internal change`
