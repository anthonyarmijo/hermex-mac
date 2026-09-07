# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | Maintainer needs to evaluate this issue |
| `needs-info` | `needs-info` | Waiting on reporter for more information |
| `ready-for-agent` | `ready-for-agent` | Fully specified, ready for an AFK agent |
| `ready-for-human` | `ready-for-human` | Requires human implementation |
| `wontfix` | `wontfix` | Will not be actioned |

When a skill mentions a role, use the corresponding label string from this table.

## Routing flags

These labels combine with a triage role; they do not replace it.

| Label | Combines with | Meaning |
| --- | --- | --- |
| `needs-manual-validation` | `ready-for-agent` | Prepare and push a draft PR while automated work continues. The owner must complete the requested manual checks before the PR becomes ready or merges; no separate permission is needed for each implementation stage. |

Apply `needs-manual-validation` sparingly: only when automated tests genuinely cannot cover the risk (gestures, share extension, live activities, streaming UI).

| Label | Combines with | Meaning |
| --- | --- | --- |
| `upstream-change` | any triage role | The root cause is in hermes-webui/hermes-agent, not this app. Link the upstream issue on the ticket. As a client repo, a chunk of incoming bugs are really server bugs. |

> **Why no `needs-response` label?** It was considered ("maintainer replied, waiting on reporter") and judged redundant: `needs-info` already means the ball is in the reporter's court. Keep `needs-info` as the single waiting-on-reporter label.

## Component labels

`area:*` labels route external issue volume to the affected subsystem. They share one color family (`#006B75`), combine freely with the triage roles above, and an issue may carry more than one.

| Label | Covers |
| --- | --- |
| `area:streaming` | Streaming chat responses (SSE, run lifecycle) |
| `area:auth` | Login, session cookies, Keychain credentials |
| `area:voice` | Voice notes, dictation, speech-to-text |
| `area:live-activity` | Live Activities and Dynamic Island |
| `area:i18n` | Localization, RTL, plurals, translations |
| `area:share-extension` | Share extension |
| `area:widgets` | Home/lock screen widgets and App Intents |
| `area:settings` | Settings and appearance |
| `area:networking` | Connectivity, ATS, tunnels, Tailscale |

If the GitHub repository does not yet have these labels, create them before applying them.
