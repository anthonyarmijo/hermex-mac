import XCTest
import UIKit
import SwiftUI
import MarkdownUI
@testable import HermesMobile

@MainActor
final class BoundedImageCacheTests: XCTestCase {
    private func fixture(_ size: Int = 64, alpha: Bool = false) throws -> Data {
        try PerformanceBaselineFixtures.imageData(width: size, height: size, transparent: alpha)
    }

    func testMarkdownLoaderDownsamplesAndSharesMediaCache() async throws {
        let data = try fixture(4_096, alpha: true)
        let cache = TranscriptMediaImageCache()
        let url = URL(string: "https://fixture.invalid/image")!
        let loader = TranscriptMarkdownImageLoader(namespace: "one", loadData: { reference in
            XCTAssertEqual(reference.id, url.absoluteString)
            return data
        }, cache: cache)
        let image = await loader.image(at: url)
        let cg = try XCTUnwrap(image?.cgImage)
        XCTAssertEqual(max(cg.width, cg.height), 2_048)
        XCTAssertTrue([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(cg.alphaInfo))
        let mediaHit = await cache.image(for: .init(rawReference: url.absoluteString), cacheNamespace: "one") { _ in
            XCTFail("Markdown and MEDIA must share their cached pixels"); return nil
        }
        XCTAssertTrue(image === mediaHit)
        let other = TranscriptMarkdownImageLoader(namespace: "two", loadData: { _ in nil }, cache: cache)
        let isolated = await other.image(at: url)
        XCTAssertNil(isolated)
        let snapshot = await cache.diagnosticSnapshot()
        XCTAssertEqual(snapshot.hits, 1)
        XCTAssertLessThanOrEqual(snapshot.costBytes, ImageCachePolicy.media.maximumCostBytes)
    }

    func testMarkdownLoaderRejectsNonHTTPAndCancelledRequests() async {
        let loader = TranscriptMarkdownImageLoader(namespace: "reject", loadData: { _ in
            XCTFail("Rejected request reached transport"); return nil
        }, cache: TranscriptMediaImageCache())
        for value in ["file:///private/image.png", "javascript:alert(1)", "data:image/png;base64,abc"] {
            let image = await loader.image(at: URL(string: value)!)
            XCTAssertNil(image)
        }
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await loader.image(at: URL(string: "https://fixture.invalid/cancelled")!)
        }
        let image = await cancelled.value
        XCTAssertNil(image)
    }

    func testHostedMarkdownBlockAndInlineUseInjectedTransport() async throws {
        let block = expectation(description: "Block provider loads through app transport")
        let inline = expectation(description: "Inline provider loads through app transport")
        let data = try fixture()
        let content = VStack {
            Markdown("![Block](https://fixture.invalid/block.png)")
            Markdown("Before ![Inline](https://fixture.invalid/inline.png) after")
        }.boundedTranscriptMarkdownImages(namespace: UUID().uuidString) { reference in
            if reference.id.hasSuffix("/block.png") { block.fulfill() }
            else if reference.id.hasSuffix("/inline.png") { inline.fulfill() }
            else { XCTFail("Unexpected image reference") }
            return data
        }
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.layoutIfNeeded()
        await fulfillment(of: [block, inline], timeout: 5)
    }

    func testCountAndByteLimitsEvictLeastRecentlyUsed() async throws {
        let data = try fixture()
        let cache = BoundedImageCache(policy: .init(maximumEntries: 2, maximumCostBytes: 40_000, maximumPixelSize: 64))
        for key in ["a", "b", "a", "c"] { _ = await cache.image(namespace: "one", resource: key) { data } }
        let snapshot = await cache.diagnosticSnapshot()
        XCTAssertEqual(snapshot.entries, 2)
        XCTAssertEqual(snapshot.evictions, 1)
        XCTAssertEqual(snapshot.hits, 1)
        XCTAssertLessThanOrEqual(snapshot.costBytes, 40_000)
        _ = await cache.image(namespace: "one", resource: "a") { XCTFail("Recently used image was evicted"); return nil }
        _ = await cache.image(namespace: "one", resource: "b") { data }
        let final = await cache.diagnosticSnapshot()
        XCTAssertEqual(final.misses, 4)
        let byteLimited = BoundedImageCache(policy: .init(maximumEntries: 99, maximumCostBytes: 20_000, maximumPixelSize: 64))
        for key in ["a", "b", "c"] { _ = await byteLimited.image(namespace: "one", resource: key) { data } }
        let bytes = await byteLimited.diagnosticSnapshot()
        XCTAssertEqual(bytes.entries, 1)
        XCTAssertEqual(bytes.evictions, 2)
    }

    func testOversizedAndMalformedImagesAreNotRetainedAndCanRetry() async throws {
        let data = try fixture()
        let cache = BoundedImageCache(policy: .init(maximumEntries: 3, maximumCostBytes: 1, maximumPixelSize: 64))
        let valid = await cache.image(namespace: "n", resource: "p") { data }
        XCTAssertNotNil(valid)
        let malformed = await cache.image(namespace: "n", resource: "p") { Data("bad image".utf8) }
        XCTAssertNil(malformed)
        let retry = await cache.image(namespace: "n", resource: "p") { data }
        XCTAssertNotNil(retry)
        let snapshot = await cache.diagnosticSnapshot()
        XCTAssertEqual(snapshot.entries, 0)
        XCTAssertEqual(snapshot.inFlight, 0)
        XCTAssertEqual(snapshot.misses, 3)
    }

    func testServerSessionNamespacesAndPrivateKeys() async throws {
        let data = try fixture()
        let cache = BoundedImageCache(policy: .attachments)
        for namespace in ["server-a/session-a", "server-b/session-a", "server-a/session-b"] {
            _ = await cache.image(namespace: namespace, resource: "same-private-path") { data }
        }
        let before = await cache.diagnosticSnapshot()
        XCTAssertEqual(before.misses, 3)
        await cache.remove(namespace: "server-a/session-a")
        let after = await cache.diagnosticSnapshot()
        XCTAssertEqual(after.entries, 2)
        let key = PrivateImageCacheKey(namespace: "https://user:secret@server/path", resource: "?token=secret")
        XCTAssertEqual(key.namespace.count, 64)
        XCTAssertFalse(String(describing: key).contains("secret"))
        let url = URL(string: "https://server.example")!
        let first = ImageCacheIdentity.namespace(server: url, session: "same")
        ImageCacheIdentity.invalidate()
        XCTAssertNotEqual(first, ImageCacheIdentity.namespace(server: url, session: "same"))
    }

    func testLargeTransparentAndOrientedImagesDownsampleWithoutLosingAlpha() async throws {
        let data = try fixture(1_024, alpha: true)
        let cache = BoundedImageCache(policy: .attachments)
        let image = await cache.image(namespace: "a", resource: "alpha") { data }
        let cg = try XCTUnwrap(image?.cgImage)
        XCTAssertEqual(max(cg.width, cg.height), 512)
        XCTAssertTrue([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(cg.alphaInfo))
        let preview = try XCTUnwrap(ImagePreviewDownsampler.previewData(from: data, maxPixelSize: 128))
        XCTAssertEqual(Array(preview.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let rotated = try PerformanceBaselineFixtures.imageData(width: 256, height: 512, transparent: false, orientation: .right)
        let oriented = await cache.image(namespace: "a", resource: "rotation") { rotated }
        XCTAssertEqual(oriented?.imageOrientation, .up)
        XCTAssertEqual(oriented?.cgImage?.width, 512)
        XCTAssertEqual(oriented?.cgImage?.height, 256)
    }

    func testCoalescedConsumerCancellationDoesNotCancelOtherConsumer() async throws {
        let data = try fixture()
        let loader = SuspendedImageLoader(data: data)
        let cache = BoundedImageCache(policy: .attachments)
        let first = Task { await cache.image(namespace: "n", resource: "p") { await loader.load() } }
        await loader.waitUntilStarted()
        let second = Task { await cache.image(namespace: "n", resource: "p") { XCTFail("Duplicate loader"); return nil } }
        for _ in 0..<1_000 {
            if await cache.diagnosticSnapshot().hits == 1 { break }
            await Task.yield()
        }
        let joined = await cache.diagnosticSnapshot()
        XCTAssertEqual(joined.hits, 1)
        first.cancel()
        let cancelled = await first.value
        XCTAssertNil(cancelled)
        await loader.finish()
        let retained = await second.value
        XCTAssertNotNil(retained)
        let done = await cache.diagnosticSnapshot()
        XCTAssertEqual(done.entries, 1)
        XCTAssertEqual(done.inFlight, 0)
    }

    func testInvalidationCancelsWaitersAndLateLoadCannotPoisonReplacement() async throws {
        let data = try fixture()
        let loader = SuspendedImageLoader(data: data)
        let cache = BoundedImageCache(policy: .attachments)
        let first = Task { await cache.image(namespace: "n", resource: "p") { await loader.load() } }
        await loader.waitUntilStarted()
        await cache.removeAll()
        let cancelled = await first.value
        XCTAssertNil(cancelled)
        let replacement = await cache.image(namespace: "n", resource: "p") { data }
        XCTAssertNotNil(replacement)
        await loader.finish()
        let hit = await cache.image(namespace: "n", resource: "p") { XCTFail("Late completion removed replacement"); return nil }
        XCTAssertNotNil(hit)
        let snapshot = await cache.diagnosticSnapshot()
        XCTAssertEqual(snapshot.entries, 1)
        XCTAssertEqual(snapshot.inFlight, 0)
    }

    func testLastConsumerCancellationAllowsRetry() async throws {
        let data = try fixture()
        let loader = SuspendedImageLoader(data: data)
        let cache = BoundedImageCache(policy: .attachments)
        let task = Task { await cache.image(namespace: "n", resource: "p") { await loader.load() } }
        await loader.waitUntilStarted()
        task.cancel()
        let cancelled = await task.value
        XCTAssertNil(cancelled)
        let snapshot = await cache.diagnosticSnapshot()
        XCTAssertEqual(snapshot.inFlight, 0)
        await loader.finish()
        let retry = await cache.image(namespace: "n", resource: "p") { data }
        XCTAssertNotNil(retry)
    }

    func testMemoryWarningPurgesRetainedImages() async throws {
        let data = try fixture()
        let cache = BoundedImageCache(policy: .attachments)
        _ = await cache.image(namespace: "n", resource: "p") { data }
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        for _ in 0..<1_000 {
            if await cache.diagnosticSnapshot().entries == 0 { break }
            await Task.yield()
        }
        let snapshot = await cache.diagnosticSnapshot()
        XCTAssertEqual(snapshot.entries, 0)
        XCTAssertEqual(snapshot.costBytes, 0)
    }

    func testUniqueLargeImagesReachStableDecodedCost() async throws {
        let data = try PerformanceBaselineFixtures.imageData(width: 4_096, height: 3_072, transparent: false)
        let cache = BoundedImageCache(policy: .media)
        let clock = ContinuousClock()
        var cold: [Double] = [], warm: [Double] = []
        var costs: [Int] = []
        var before = rusage(), after = rusage()
        getrusage(RUSAGE_SELF, &before)
        for index in 0..<48 {
            let start = clock.now
            let image = await cache.image(namespace: "stress", resource: "unique-\(index)") { data }
            XCTAssertEqual(image?.cgImage?.width, 2_048)
            let duration = start.duration(to: clock.now).components
            cold.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            let hitStart = clock.now
            _ = await cache.image(namespace: "stress", resource: "unique-\(index)") { XCTFail("Warm miss"); return nil }
            let hitDuration = hitStart.duration(to: clock.now).components
            warm.append(Double(hitDuration.seconds) * 1_000 + Double(hitDuration.attoseconds) / 1e15)
            let snapshot = await cache.diagnosticSnapshot()
            XCTAssertLessThanOrEqual(snapshot.costBytes, ImageCachePolicy.media.maximumCostBytes)
            if index % 8 == 7 { costs.append(snapshot.costBytes) }
        }
        getrusage(RUSAGE_SELF, &after)
        XCTAssertEqual(Set(costs).count, 1)
        let snapshot = await cache.diagnosticSnapshot()
        XCTAssertGreaterThan(snapshot.evictions, 0)
        func percentile(_ values: [Double], _ fraction: Double) -> Double {
            values.sorted()[min(values.count - 1, Int((Double(values.count) * fraction).rounded(.up)) - 1)]
        }
        print("[PERF] BoundedImageStress unique=48 dimensions=4096x3072 retainedEntries=\(snapshot.entries) decodedCostBytes=\(snapshot.costBytes) checkpoints=\(costs) evictions=\(snapshot.evictions) hits=\(snapshot.hits) misses=\(snapshot.misses) coldP50Ms=\(percentile(cold, 0.5)) coldP95Ms=\(percentile(cold, 0.95)) warmP50Ms=\(percentile(warm, 0.5)) warmP95Ms=\(percentile(warm, 0.95)) processHighWaterBeforeBytes=\(before.ru_maxrss) processHighWaterAfterBytes=\(after.ru_maxrss)")
    }

    func testLinkPreviewByteBudgetAndReplacementAccounting() async {
        let cache = TranscriptLinkPreviewCache(maximumEntryCount: 10, maximumCostBytes: 10)
        let a = URL(string: "https://example.com/a")!, b = URL(string: "https://example.com/b")!
        await cache.store(.init(imageData: Data(repeating: 0, count: 6)), for: a)
        await cache.store(.init(imageData: Data(repeating: 0, count: 6)), for: b)
        let evicted = await cache.snapshot(for: a)
        XCTAssertNil(evicted)
        await cache.store(.init(imageData: Data(repeating: 0, count: 2)), for: b)
        let cost = await cache.diagnosticCostBytes()
        XCTAssertEqual(cost, 2)
        await cache.store(.init(imageData: Data(repeating: 0, count: 11)), for: b)
        let rejected = await cache.diagnosticCostBytes()
        XCTAssertEqual(rejected, 0)
    }
}

private actor SuspendedImageLoader {
    let data: Data
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Data?, Never>?
    init(data: Data) { self.data = data }
    func load() async -> Data? {
        started = true
        startWaiter?.resume(); startWaiter = nil
        return await withCheckedContinuation { completion = $0 }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func finish() { completion?.resume(returning: data); completion = nil }
}
