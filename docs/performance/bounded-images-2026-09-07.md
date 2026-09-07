# Bounded image caches — September 7, 2026

Issue #15, based on the v1.6.0 integration plus the explicit composer gesture fix.
These are synthetic Debug measurements on the same Mac/Xcode 26.6 environment,
not claims about scrolling frame rate or release-build speed.

## Implementation and inventory

| Surface | Retention and policy |
| --- | --- |
| Attachment tiles | Shared actor: 96 entries, 16 MiB decoded pixels, 512-pixel longest side |
| Inline transcript media | Shared actor: 48 entries, 64 MiB decoded pixels, 2048-pixel longest side |
| Link preview snapshots | Existing 96-entry LRU plus 8 MiB of image data, title and display-URL bytes |
| Composer/pending thumbnails | View/coordinator state; existing 512-pixel preview path |
| File/media preview | View-local 2048-pixel preview; explicit export continues to read original bytes |
| Math renderability | NSCache of Boolean parse results, not decoded images; unchanged |

The two decoded-image caches share an internal, dependency-free actor. Cost is
`CGImage.bytesPerRow * height`, not compressed input size. Count and byte caps
both evict least-recently-used entries. Oversized entries can be displayed but
are not retained. Missing/invalid images leave no poisoned cache entry.
The attachment tier serves small grid cells; the media tier supports a roughly
1024-point retina inline preview without globally retaining 4K originals.
These are conservative caps, not empirically optimal limits for every device.

Keys hash namespace and resource identity. The namespace includes server,
session and an observable authentication epoch. Attachment tasks and view
identity now include that namespace. Unscoped callers cannot reuse cache keys.
Changing authentication, active server or custom headers invalidates the epoch
synchronously, then conservatively purges shared image caches. Removing an
account also purges them. The lower-level namespace removal API selectively
preserves other namespaces; authentication transitions currently favor a full
purge over retaining another account's warm images.

Concurrent consumers share a load. Cancelling one waiter leaves other consumers
running; cancelling the last waiter cancels the underlying task and permits a
retry. Reset cancels/resumes waiters and generation-checks late completions.
ImageIO creates transformed, immediately decoded thumbnails off the main actor,
without constructing a full-resolution UIImage or re-encoding an intermediate
JPEG. Large alpha-bearing previews now encode PNG. Static thumbnail behavior is
preserved; original-file export remains separate.

UIKit memory warnings and Darwin warning/critical memory-pressure events purge
both decoded caches and link snapshots. Diagnostics contain counts/costs, not
server addresses, paths or credentials.

## Measurements

The original four-image fixture was run before and after on the same machine.
It contains two 64-pixel images and two 2048×1536 images, so the new 2048 tier
intentionally retains the same decoded cost. Four samples are too few for a
strong tail-latency conclusion.

| Four-image fixture | Before | After |
| --- | ---: | ---: |
| Decoded cache bytes | 25,198,592 | 25,198,592 |
| Cold median / p95 ms | 2.289 / 87.815 | 0.653 / 16.422 |
| Warm median / p95 ms | 0.027 / 3.763 | 0.092 / 0.122 |
| Separate downsample median / p95 ms | 1.351 / 1.379 | 1.168 / 1.218 |

The added 48-unique-image stress test uses 4096×3072 input and reloads each image
once while warm. At each eight-image checkpoint, decoded retention is exactly
62,914,560 bytes (five images), with 43 evictions, 48 hits and 48 misses. Cold
p50/p95 are 14.649/19.930 ms; warm p50/p95 are 0.098/0.128 ms in the focused run.
The test process's cumulative `getrusage` resident high-water mark changes from
205,291,520 to 589,578,240 bytes. That includes fixture construction, decoding,
frameworks and test-host allocations; it is neither current cache size nor a
controlled old/new RSS comparison. A retained-pixel bound does not imply an
identical process-memory bound.

## Validation and limits

Ten focused Mac tests cover count/byte LRU, oversize rejection and retries,
server/session identity, alpha/orientation, shared cancellation, last-waiter
cancellation, invalidation races, memory warnings, link-byte replacement and
stable retention under unique-image stress. Full Mac suite: 2359 tests, four
expected skips, zero failures. All ten focused iPhone tests pass. The signed Mac app passes strict signature
verification.

Full evidence is retained in `.codex-tmp/mac-modernization/`: `ImagesBefore`,
`ImagesFocused2`, `ImagesFocused4`, `ImagesMacFull`, and `ImagesIPhone` result
bundles and corresponding logs. The desktop remains locked, so signed normal
UI review, image-heavy scrolling hitches, visual preview/export checks and
real display-scale comparisons remain pending. No unsupported smoothness or
energy improvement is claimed.
