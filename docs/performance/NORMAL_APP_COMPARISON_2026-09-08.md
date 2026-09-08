# Normal Mac app comparison — September 8, 2026

This continues the [integrated measurements](INTEGRATED_MODERNIZATION_2026-09-07.md)
and [normal UI validation](NORMAL_APP_VALIDATION_2026-09-07.md). The investigation
is still in progress. Fresh-process startup has repeated measurements; warm
activation and controlled image-scroll/resize comparisons are not yet complete.

## Isolation and method

The baseline is `6ceaa5c`; the candidate app code is `60a356a`. Both were built
with Xcode 26.6, arm64 Debug Mac Catalyst, coverage disabled, on the same M4 Mac
with 24 GB RAM and macOS 26.6.2. They use separate development-signed bundle IDs,
containers, Keychain services and app-group identifiers. Xcode automatic
provisioning supplied the matching development profile. Only the profiling
copies' executable/display names and URL schemes were changed after building;
their signatures were verified again. The owner's ordinary app and credentials
were not used for these comparisons.

Both normal apps connected to the same loopback-only fixture. The selected
transcript contains 512 deterministic text messages, alternating user/assistant,
with a code block in each assistant message. Both isolated SwiftData stores held
the same 536 messages across that transcript and the existing 24-image fixture.
No XCTest host or Streaming Lab was used for the recorded launches.

“Fresh process” means the app was quit normally before each launch. Its data and
filesystem caches remained warm; this is not a reboot-cold or cleared-disk-cache
test. Finder opened the app into the foreground. Background launches through the
automation app-selection API did not provide usable first-frame events and were
excluded. A Time Profiler recording captured the foreground lifecycle intervals.
Four samples per version were completed, with the version order varied between
pairs. Ordinary background apps remained open. These small samples describe this
machine and fixture, not population-level latency or a release-build guarantee.

## Fresh-process startup with a cached transcript

The first metric runs from Instruments' process-exec interval start through the
end of its `Launching - Initial Frame Rendering` interval. The second is that
rendering interval alone. Neither includes the automation command's dispatch
time. Initial frame rendering does not by itself prove all chat content is ready.

| Metric, four samples each | Baseline median | Candidate median | Baseline range | Candidate range |
| --- | ---: | ---: | ---: | ---: |
| Process exec → end of initial frame | 339.99 ms | 352.58 ms | 330.21–353.52 ms | 337.17–373.10 ms |
| Initial frame rendering phase | 171.11 ms | 184.47 ms | 164.88–183.72 ms | 168.94–186.34 ms |

The candidate median is about 12.6 ms higher to the initial frame. There is no
startup speedup claim. With four samples, the table gives the observed range,
not a reliable percentile tail.

The first subsequent accessibility observation contained `Cached message 512`
in all eight launches. Finder-open → that observation ranged from 2,643 to
2,767 ms before and 2,223 to 2,354 ms after. Those values include automation,
activation and observation waits; they are retained as content-readiness evidence
and must not be presented as intrinsic app latency or a measured speedup.

## Image comparison uncovered a production wiring gap

The normal candidate displayed a large Markdown image narrower than the baseline
at the same captured window size. The production view supplied an already
downsampled 512-pixel attachment preview to the bounded media cache. The cache's
2,048-pixel policy could not recover the original dimensions or detail. Existing
provider tests supplied original 4K bytes directly and therefore missed this
production binding.

The follow-up routes original compressed media bytes into the bounded cache,
which owns decoding and downsampling. This also avoids the earlier preview
re-encoding step. The full signed Mac suite passed with 2,370 tests, five expected skips and no
failures in a verified separate test identity; the iPhone simulator build passed.
The corrected signed normal app then displayed the same large image at the
baseline width in matching 1,024 × 768 captures. The existing raw-data/export
path is unchanged. The matched scroll/resize timing comparison remains pending;
earlier captures with the smaller image footprint are not evidence of
equivalent-layout performance.

Native automation subsequently timed out while reading the benchmark window.
The attempted scroll/resize setup is excluded from quantitative results. Warm
activation and repeated controlled scroll/resize timing still need a working
native control path; this is a validation gap, not evidence of an app hang.

## Retained local evidence

The ignored `normal-benchmark` directory contains signed profiling copies and
their manifests, build/signing logs, `MatchedForegroundLaunches.trace`, lifecycle
XML, per-process results, summary statistics and automation observations. The
fixture source and request log are preserved separately. Failed initial signing
attempts and background-launch pilots are recorded and excluded from the results.
No private server address, credential or user transcript is included here.
