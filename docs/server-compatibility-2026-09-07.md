# Running-server compatibility — September 7, 2026

The current Mac candidate successfully decoded 27 read-only responses through
its production APIClient and models, using an ephemeral cookie session. The
running server reported WebUI `exp-v0.52.215` and agent
`v2026.8.27-432-g4209d371aa`. This does not upgrade the server or establish every
feature's end-to-end compatibility.

| Area | Observed result |
| --- | --- |
| Health, authentication, settings/version | Decoded; health status `ok`; isolated password login succeeded |
| Sessions, one session's metadata and status | Decoded; no message generation, import or history mutation |
| Models, providers, reasoning, profiles, personalities, commands | Decoded |
| Workspace registry and directory listing (`/api/list`) | Decoded |
| Tasks list/status/recent runs/delivery options and one output | Decoded |
| Skills/list and one skill's content; memory | Decoded |
| Usage/insights | Decoded |
| Kanban configuration and boards | Decoded |
| Git information and status for the selected existing session | Decoded |
| File content/raw bytes, media export | Not live-checked: needs a selected safe file; deterministic app tests cover these paths |
| Chat/SSE generation, session mutations, task execution, Kanban mutations/dispatch | Deterministic tests only; no live operations performed |
| Authentication/chat from a second Mac | Owner smoke still pending |

Check names in the JSON report are operation labels; the APIClient owns the
actual endpoint paths and payload decoding. Optional fields may legitimately
be absent. A successful decode is not proof that every optional capability is
available or that its complete UI flow was exercised.

The isolated cookie jar never replaced the app's cookies or Keychain values.
Only login and reads were sent. No logout was sent to the owner's session, no
service was restarted, and no server/network setting or existing session was
changed. Only sanitized result categories and version strings are retained;
responses, IDs, file contents, passwords and cookies are not in the report.
The generated ignored credential input was removed after the check.

## Reproducible opt-in harness

`HermesReadOnlyCompatibility` explicitly enables
`LiveServerReadCompatibilityTests`. The normal app scheme skips it. Supply an
ignored, owner-readable `.codex-tmp/live-read-config.json` with `serverURL` and,
when required, `password`. Never commit that file. The test uses a 12-second
request and 20-second resource timeout, records a sanitized XCTest attachment,
and prints only operation/result categories and versions. No extra dependency
or persistent machine setting is required.

Run the scheme's focused test with signed Mac Catalyst, code coverage disabled,
using the same terminal build setup as DEVELOPMENT.md. Remove the temporary
credential input after running. Full evidence for this run is retained locally
in `LiveReadCompatibility2.xcresult`, `live-read-compatibility-2.log` and the
sanitized `live-read-report.json` under `.codex-tmp/mac-modernization/`.
The initial attempt completed reads but could not save its report outside the
app sandbox; reporting now uses XCTest attachments without weakening signing.

## Backend pin and upgrade decision

`UPSTREAM_TESTED_SHA` remains `f1d399b437c1ca7fe4b6d2093aebe334c32f34a3`
(v0.51.85). CONTRACT_TESTS.md requires both read groups and a disposable-session
mutation smoke before advancing it. Neither a healthy server nor this expanded
read-only pass satisfies that complete gate. The current live backend checkout
and its reported runtime versions are recorded separately in local CURRENT.md.

No tested read requires an immediate backend upgrade. This result is insufficient
to claim that all new mutation/SSE contracts work on the current deployment.
Before considering an upgrade, compare the exact required contract in the current
running source, back up its configuration/session/workspace state, pin a reviewed
candidate, and prepare a rollback to the current checkout and backups. Restart,
network, LaunchAgent and server-version changes require operation-specific
approval; none has been performed here.

A separate approved smoke may create one clearly named disposable session,
exercise supported rename/pin/archive/move/branch/truncate/delete flows only
within that disposable data, then remove it and verify cleanup. If a generated
response is needed for replay/SSE testing, specify the test prompt, model and
budget before approval. Never reuse an owner's session. This is a preparation
plan, not authorization to execute it.
