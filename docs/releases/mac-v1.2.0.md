## Highlights

- Check your server connection from the Mac sidebar or Settings. See the configured address, reachability, sign-in status, WebUI and agent versions, and the time and latency of the last check. Copy the address or jump to the existing server settings and sign-in flows.
- A redesigned chat makes long agent runs easier to follow: compact tool and thinking rows, expandable finished turns, timestamps and copy actions, and clearer working-time indicators.
- Reference workspace files with `@path` chips, choose skills at the caret, send attachments without text, and keep unsent text, attachments and composer choices across navigation and relaunches.
- Browse a lazy workspace tree, read syntax-colored source files, and review all changed Git files in one surface with word highlights, file folding and line selection for the composer.
- Image-heavy chats use bounded thumbnail caches, and Git review prepares each loaded diff once instead of repeatedly parsing earlier files.

## Improvements

- Tasks now has an agenda, useful filters, recent runs and per-task history. Task configuration includes model, provider and profile choices.
- Usage offers time-window charts and clearer cost and token summaries. Missing server metrics remain unavailable rather than being invented.
- Kanban is available in normal navigation, including board/card workflows, bulk actions and dispatcher controls where the server supports them. The browsed board is restored per server.
- Session rows show when approval, input or work is pending; search explains matches. External CLI and messaging sessions use the server's import flow and respect read-only results.
- Partial-response recovery, late-event handling, scroll-position preservation and session-scoped reasoning settings include upstream fixes.
- Settings can hide unused sections and show optional response-speed metrics. Model choices retain their provider identity.
- Remote Markdown images and extensionless image previews share the bounded media cache. Large transparent thumbnails preserve transparency. Image caches distinguish servers and sessions, handle cancellation safely and release retained images under memory pressure.
- Existing Mac commands, dedicated Settings, file export, signing identity and offline-cache improvements remain in place. Older Mac text drafts migrate into the newer durable draft store.
- Includes the Mac 1.1.1 window-expansion, background cache-write and streaming improvements.

## Server requirements

Hermex is a client for a separately running hermes-webui server. The server
machine must remain awake and reachable. On another Mac, `localhost` refers to
that other Mac; use the server machine's reachable address instead. Installing
Hermex does not install or update the server.

The client integrates stable upstream Hermex v1.6.0 plus its composer-selection
correction. Read-only compatibility was checked against WebUI exp-v0.52.215 and
agent v2026.8.27-432-g4209d371aa. Optional features depend on the APIs and
capabilities your server provides; this client update does not upgrade them.

## Known issues

- Rich Markdown can still be the main cost in long-chat rendering. Bounded image retention and fewer diff parses do not eliminate every interface pause.
- Passkey-only and browser-based SSO sign-in are not supported. A trusted-header deployment works only when its proxy authenticates the app's request.
- Updates remain manual: download and install the newer Mac DMG from GitHub Releases.
- The existing Mac interface mode is retained. The alternate Optimize Interface for Mac mode needs compatibility work before adoption.
