# Normal Mac app comparison — September 8, 2026

This continues the [integrated measurements](INTEGRATED_MODERNIZATION_2026-09-07.md)
and [normal UI validation](NORMAL_APP_VALIDATION_2026-09-07.md). The investigation
includes repeated fresh-process launches, warm reopen and window-resize checks,
and an image-scroll comparison with a reproducible baseline failure. The limits
below distinguish app lifecycle measurements from automation timings.

## Isolation and method

The baseline is `6ceaa5c`. Startup used candidate `60a356a`; subsequent warm
reopen, resizing and image scrolling used `1eaa41c`, which corrects the production
image input described below. The text-startup code is unchanged. Both were built
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
path is unchanged. Earlier captures with the smaller image footprint are not
evidence of equivalent-layout performance.

## Image scrolling: baseline hangs, candidate stays responsive

The first apparent native-control failure was subsequently confirmed as a real
baseline app hang. Outside the recorded reproduction, macOS marked Hermex Before
“not responding”; it consumed about 100% of one CPU, and all 781 main-thread
samples were in SwiftUI/AttributeGraph layout and transaction work. Its sampled
physical footprint was 1.2 GB, with a 1.3 GB peak. These are process measurements,
not the bounded cache's retained-byte count or a matched memory comparison.

After relaunching, the same 24-image fixture reproduced the failure under an
app-scoped Animation Hitches/Time Profiler capture. Starting at image 24 in a
1,024 × 768 capture, each cycle scrolled up six pages, down six pages, then used
Scroll to latest when available. The baseline completed one cycle and hung on
the second. Another process sample showed roughly one CPU busy and a 1.0 GB
physical footprint, with a 1.2 GB peak. Only the disposable benchmark process was
force-quit; the ordinary user app and its data were untouched.

The corrected candidate completed four cycles without a timeout and remained
responsive afterward. Three immediate end-of-cycle observations included image
24; the third was taken during a transient layout state, and the next cycle and
final observation showed image 24. Native scroll inertia produced different
visible row ranges between cycles and versions. This supports the responsiveness
finding, not a claim of identical per-frame workloads or a measured FPS gain.
The versions differ in multiple upstream and cache changes, so this does not
isolate the cause of the baseline hang or prove one cache change fixed it.

The baseline reproduction trace saved successfully. The candidate's Animation
Hitches capture failed during saving after profiler temporary files exhausted
disk space; it is excluded from quantitative comparison. Its successful native
interactions remain recorded separately. There is no valid paired hitch/FPS or
peak-memory result from that attempt. The older patch candidate was not tested
with this reproduction and must not be assumed to resolve the baseline failure.

## Warm reopen and controlled resizing

Both processes remained running with the same cached 512-message text transcript.
Finder brought each app back to the foreground four times. Every first subsequent
accessibility observation contained message 512. Four paired resize cycles per
version changed the captured window from 1,024 × 768 to 864 × 648 and back.
All 16 small/large observations retained message 512, and every captured size
matched the requested comparison geometry. These are screenshot pixels, not
independently measured native desktop points. The normal available-display
expansion/full-screen checks are recorded separately in the UI validation report.

The following values measure the complete automation workflow. Warm reopen runs
from Finder's Open action through the accessibility observation. A resize cycle
includes both drags, two screenshot encodings and two accessibility observations.
They include tool dispatch/waits and therefore cannot establish intrinsic app
latency, animation smoothness or a percentage performance improvement.

| Workflow, four samples each | Baseline median | Candidate median | Baseline range | Candidate range |
| --- | ---: | ---: | ---: | ---: |
| Already-running app reopen → cached content observed | 1,357 ms | 1,462 ms | 1,063–1,496 ms | 1,375–1,618 ms |
| Shrink + expand + content/geometry observations | 3,182.5 ms | 2,091 ms | 3,064–3,513 ms | 1,616–3,087 ms |

A matched 90-second Time Profiler trace was saved for these actions. Its
`potential-hangs` table, configured to include stalls longer than 250 ms,
contained zero entries for either benchmark app. This does not establish FPS
or exclude shorter stalls. Process-cold
startup is represented by the earlier fresh-process launches, and the warm case
here means reopening an already-running app. Neither represents reboot-cold disk
caches. Range is reported instead of a statistically unsupported percentile tail.
The workflows completed; their overhead prevents a universal responsiveness claim.

## Retained local evidence

The ignored `normal-benchmark` directory contains signed profiling copies and
their manifests, build/signing logs, `MatchedForegroundLaunches.trace`, lifecycle
XML, per-process results, summary statistics, `MatchedWarmResize.trace`, resize
and warm-reopen observations, image-scroll actions and both baseline hang samples. The
fixture source and request log are preserved separately. Failed initial signing
attempts and background-launch pilots are recorded and excluded from the results.
No private server address, credential or user transcript is included here.

Seven compiler module-cache directories and seven compiler-intermediate
directories were removed after verifying no build was active; signed products
and final results were preserved. Two closed profiler temporary recordings were
compressed and their complete decompressed SHA-256 checksums verified before
removing the redundant originals. Cleanup manifests and the archives are retained.
