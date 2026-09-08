## Highlights

- Expand the Mac window to use your available desktop space, including larger displays, and return from full screen without the old size cap.

- Long responses stream more efficiently, reducing repeated text processing as replies grow.
- Large offline-cache updates run in the background and use fewer database operations, reducing work competing with the interface.

## Improvements

- Responses without math notation take a faster Markdown formatting path.
- Streaming preserves word pacing, Unicode text, reconnect recovery, and the complete final response.

## Known issues

- Rich Markdown layout can still be the main cost when displaying long responses; this release does not eliminate all rendering pauses.
- Updates remain manual: download and install the newer DMG from GitHub Releases.
- Hermex requires a reachable, separately running hermes-webui server. Installing Hermex on another Mac does not install the server there.
