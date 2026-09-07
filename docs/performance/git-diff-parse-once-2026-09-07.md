# Prepare Git review once — September 7, 2026

Issue #17, following bounded images at 847b692.

The integrated upstream already moved parsing out of SwiftUI body evaluation
and built its review surface off the main thread. Collapse, selection and
appearance changes therefore did not need the older planned body-parser fix.
However, each arriving file rebuilt all rows from raw loaded diffs, reparsing
previous results. Eight textual responses caused 1+2+…+8 = 36 parses.

Each response now becomes immutable prepared rows before loaded state is
published. Subsequent incremental rebuilds concatenate those rows. Preparation
includes fallback counts, stable IDs, line numbering and word highlights; the
production loaded state need not retain both raw diff text and prepared rows.
Binary/oversized responses still skip parsing. Empty, failed and loading notices
are unchanged. Storage lives with the review view, with no global diff cache.

Audited file/diff/row values now conform to Sendable. Structured task-group work
performs parsing outside MainActor, checks cancellation before and after work,
and returns only immutable values. MainActor publishes only a current,
non-cancelled result. A newer rebuild cancels its predecessor. Dismissal cancels
refresh/rebuild work and invalidates both generations, including an in-progress
load. Refresh requests coalesce while one is running.

## Controlled synthetic result

Same Xcode 26.6 signed arm64 Catalyst Debug test host, eight files with the
existing 5,000-line fixture, one warmup and five measured repetitions. Both
paths ran sequentially in the same focused suite; network and drawing are
excluded. Timings include all eight incremental row rebuilds and, for the new
path, preparation and task-group overhead.

| Metric | Raw incremental rebuild | Prepared incremental rebuild |
| --- | ---: | ---: |
| Parses | 36 | 8 |
| Median total ms | 1,733.564 | 390.713 |
| p95 total ms (five samples) | 1,745.596 | 403.752 |
| Additional parses on 20 unchanged rebuilds | Previously repeats each raw input | 0 |

The measured total falls approximately 77%. This is repeated row-preparation
work, not a claim that Git network loading or on-screen interaction is 77%
faster. The p95 is the maximum of a small five-sample set.

The 50/5,000/25,000-line cases preserve exactly the legacy rows, including word
ranges, while each prepares once. All subsequent rebuilds add zero parses.
Diagnostics record zero main-thread parser invocations for the new async path.
This proves execution location; it does not measure window-resize frame latency.
Existing parser, line-number, headerless-patch, selection, layout and canvas
coverage remains part of the full suite.

Focused checks also cover binary/oversized/empty notices, changed-content
refresh and cancellation. Full Mac and iPhone results are recorded in the
modernization status. Logs and result bundles are retained locally as GitBefore,
GitFocused2, GitMacFull and GitIPhone under `.codex-tmp/mac-modernization/`.
Normal signed UI checks for collapse/selection, resize and dismissal during a
live read remain pending desktop unlock; the PR stays draft for that check.
