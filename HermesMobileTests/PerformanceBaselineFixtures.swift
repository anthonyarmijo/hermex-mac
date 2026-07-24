import ImageIO
import SwiftData
import UIKit
import XCTest
@testable import HermesMobile

enum PerformanceBaselineFixtures {
    static let identity = "hermex-synthetic-performance-v1"
    static let warmupCount = 3
    static let sampleCount = 15

    static func transcriptMessages(count: Int = 50) -> [ChatMessage] {
        precondition(count >= 0)
        return (0..<count).map { index in
            let role = index.isMultiple(of: 2) ? "user" : "assistant"
            let feature = index % 10
            let body: String
            switch feature {
            case 0:
                body = """
                ## Synthetic performance note \(index)

                Long prose uses **emphasis**, a [safe fixture link](https://example.invalid/performance), and repeated words.
                \(String(repeating: "Deterministic prose sentence \(index). ", count: 24))
                """
            case 1:
                body = """
                ```swift
                let syntheticValue\(index) = Array(0..<128).map { $0 * 2 }
                print(syntheticValue\(index).count)
                ```
                """
            case 2:
                body = """
                | Item | Value |
                | --- | ---: |
                | alpha | \(index) |
                | beta | \(index + 1) |
                """
            case 3:
                body = """
                - first deterministic item
                - second item with `inline code`
                - third item with inline math $x_\(index)^2$
                """
            case 4:
                body = """
                Display math follows:
                $$
                f(x) = x^2 + \(index)
                $$
                """
            case 5 where index < 30:
                body = "Synthetic generated image:\nMEDIA:/synthetic/performance/image-\(index).png\nNo server data is used."
            default:
                body = String(repeating: "Representative long cached transcript prose \(index). ", count: 28)
            }
            return ChatMessage(
                role: role,
                content: body,
                timestamp: Double(index),
                messageId: "synthetic-message-\(index)",
                reasoning: role == "assistant" && index.isMultiple(of: 5)
                    ? "Synthetic reasoning/activity for row \(index)."
                    : nil
            )
        }
    }

    static func streamingText(characterCount: Int) -> String {
        precondition(characterCount >= 0)
        let seed = """
        👩‍👩‍👧‍👦 🇫🇷 café\r\nmultiple  spaces\tand tabs
        ```swift
        let marker = "MEDIA:/inside/fence.png"
        ```
        | column | value |
        | --- | --- |
        | alpha | $x^2$ |
        $$f(x)=x^2$$
        MEDIA:/synthetic/performance/outside.png
        ```text
        open fence stays representative
        """
        guard characterCount > 0 else { return "" }
        var result = ""
        while result.count < characterCount {
            result += seed
        }
        return String(result.prefix(characterCount))
    }

    static func awkwardSSEChunks(for text: String) -> [String] {
        let widths = [1, 7, 2, 19, 3, 31, 5, 11, 23, 4]
        var chunks: [String] = []
        var cursor = text.startIndex
        var widthIndex = 0
        while cursor < text.endIndex {
            let end = text.index(
                cursor,
                offsetBy: widths[widthIndex % widths.count],
                limitedBy: text.endIndex
            ) ?? text.endIndex
            chunks.append(String(text[cursor..<end]))
            cursor = end
            widthIndex += 1
        }
        return chunks
    }

    static func cachedMessages(count: Int) -> [ChatMessage] {
        (0..<count).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "Synthetic cached message \(index): " + String(repeating: "payload ", count: 12),
                timestamp: Double(index),
                messageId: "synthetic-cache-message-\(index)"
            )
        }
    }

    static func sessionList(count: Int = 40) throws -> [SessionSummary] {
        let rows = (0..<count).map { index in
            """
            {"session_id":"synthetic-session-\(index)","title":"Synthetic Session \(index)","workspace":"/synthetic/workspace-\(index % 4)"}
            """
        }.joined(separator: ",")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([SessionSummary].self, from: Data("[\(rows)]".utf8))
    }

    static func gitDiff(lineCount: Int) -> String {
        precondition(lineCount >= 0)
        var lines: [String] = []
        var sourceLine = 1
        while lines.count < lineCount {
            if lines.count.isMultiple(of: 250) {
                lines.append("@@ -\(sourceLine),249 +\(sourceLine),249 @@ synthetic-hunk")
            } else {
                switch lines.count % 3 {
                case 0: lines.append("-old synthetic line \(lines.count)")
                case 1: lines.append("+new synthetic line \(lines.count)")
                default: lines.append(" context synthetic line \(lines.count)")
                }
                sourceLine += 1
            }
        }
        return lines.joined(separator: "\n")
    }

    static func imageData(
        width: Int,
        height: Int,
        transparent: Bool,
        orientation: UIImage.Orientation = .up
    ) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = !transparent
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            if transparent {
                UIColor.clear.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            UIColor.systemBlue.withAlphaComponent(transparent ? 0.55 : 1).setFill()
            context.fill(CGRect(x: width / 8, y: height / 8, width: width * 3 / 4, height: height * 3 / 4))
        }
        let oriented = UIImage(cgImage: try XCTUnwrap(image.cgImage), scale: 1, orientation: orientation)
        return try XCTUnwrap(transparent ? oriented.pngData() : oriented.jpegData(compressionQuality: 0.86))
    }
}

struct PerformanceSampleSummary: Equatable {
    let sampleCount: Int
    let medianMilliseconds: Double
    let p95Milliseconds: Double

    init(nanoseconds: [UInt64]) {
        let sorted = nanoseconds.sorted()
        sampleCount = sorted.count
        guard !sorted.isEmpty else {
            medianMilliseconds = 0
            p95Milliseconds = 0
            return
        }
        medianMilliseconds = Double(sorted[(sorted.count - 1) / 2]) / 1_000_000
        let p95Index = min(Int(ceil(Double(sorted.count) * 0.95)) - 1, sorted.count - 1)
        p95Milliseconds = Double(sorted[p95Index]) / 1_000_000
    }
}

final class PerformanceBaselineFixtureTests: XCTestCase {
    func testSyntheticFixtureShapesAndPrivacyContract() throws {
        let transcript = PerformanceBaselineFixtures.transcriptMessages()
        XCTAssertEqual(transcript.count, 50)
        XCTAssertEqual(PerformanceBaselineFixtures.cachedMessages(count: 50).count, 50)
        XCTAssertEqual(PerformanceBaselineFixtures.cachedMessages(count: 500).count, 500)
        XCTAssertEqual(PerformanceBaselineFixtures.cachedMessages(count: 5_000).count, 5_000)
        XCTAssertEqual(try PerformanceBaselineFixtures.sessionList().count, 40)
        XCTAssertEqual(PerformanceBaselineFixtures.gitDiff(lineCount: 25_000).split(separator: "\n").count, 25_000)

        for count in [256, 10_000, 50_000] {
            let text = PerformanceBaselineFixtures.streamingText(characterCount: count)
            let chunks = PerformanceBaselineFixtures.awkwardSSEChunks(for: text)
            XCTAssertEqual(text.count, count)
            XCTAssertEqual(chunks.joined(), text)
        }

        let serialized = transcript.compactMap(\.content).joined()
        XCTAssertFalse(serialized.contains("/Users/"))
        XCTAssertFalse(serialized.localizedCaseInsensitiveContains("bearer "))
        XCTAssertFalse(serialized.localizedCaseInsensitiveContains("token="))
    }

    func testGitDiffParserBaselineReportsInvocationVolume() {
#if DEBUG
        GitDiffParseDiagnostics.reset()
#endif
        let lineCounts = [100, 5_000, 25_000]
        let fixtures = lineCounts.map(PerformanceBaselineFixtures.gitDiff(lineCount:))
        let clock = ContinuousClock()
        var samples: [Int: [UInt64]] = [:]
        for iteration in 0..<(PerformanceBaselineFixtures.warmupCount + PerformanceBaselineFixtures.sampleCount) {
            for (lineCount, fixture) in zip(lineCounts, fixtures) {
                let start = clock.now
                XCTAssertFalse(DiffHunk.parse(fixture).isEmpty)
                let duration = start.duration(to: clock.now).components
                if iteration >= PerformanceBaselineFixtures.warmupCount {
                    samples[lineCount, default: []].append(
                        UInt64(max(duration.seconds, 0)) * 1_000_000_000
                            + UInt64(max(duration.attoseconds, 0)) / 1_000_000_000
                    )
                }
            }
        }
#if DEBUG
        let snapshot = GitDiffParseDiagnostics.snapshot()
        XCTAssertEqual(snapshot.invocationCount, 54)
        XCTAssertGreaterThan(snapshot.bytesExamined, 0)
#endif
        for lineCount in lineCounts {
            let summary = PerformanceSampleSummary(nanoseconds: samples[lineCount] ?? [])
            let result = "GitDiffBaseline fixture=\(PerformanceBaselineFixtures.identity) lines=\(lineCount) samples=\(summary.sampleCount) medianMs=\(summary.medianMilliseconds) p95Ms=\(summary.p95Milliseconds)"
            print("[PERF] \(result)")
            XCTContext.runActivity(named: result) { _ in }
        }
    }

    @MainActor
    func testImageStressBaselineTracksColdAndWarmCacheVolume() async throws {
        let cache = TranscriptMediaImageCache()
        let imageFixtures: [(String, Data)] = [
            ("small-opaque", try PerformanceBaselineFixtures.imageData(width: 64, height: 64, transparent: false)),
            ("small-alpha", try PerformanceBaselineFixtures.imageData(width: 64, height: 64, transparent: true)),
            ("large-opaque", try PerformanceBaselineFixtures.imageData(width: 2_048, height: 1_536, transparent: false)),
            ("large-oriented", try PerformanceBaselineFixtures.imageData(width: 1_536, height: 2_048, transparent: false, orientation: .right))
        ]
        let clock = ContinuousClock()
        var cold: [UInt64] = []
        var warm: [UInt64] = []
        var downsample: [UInt64] = []

        for iteration in 0..<(PerformanceBaselineFixtures.warmupCount + PerformanceBaselineFixtures.sampleCount) {
            let start = clock.now
            XCTAssertNotNil(
                ImagePreviewDownsampler.previewData(
                    from: imageFixtures[2].1,
                    maxPixelSize: ImagePreviewDownsampler.attachmentMaxPixelSize
                )
            )
            if iteration >= PerformanceBaselineFixtures.warmupCount {
                downsample.append(Self.nanoseconds(start.duration(to: clock.now)))
            }
        }

        for (name, data) in imageFixtures {
            let reference = TranscriptMediaReference(rawReference: "/synthetic/performance/\(name).png")
            let coldStart = clock.now
            let coldImage = await cache.image(for: reference, cacheNamespace: "baseline") { _ in data }
            XCTAssertNotNil(coldImage)
            cold.append(Self.nanoseconds(coldStart.duration(to: clock.now)))

            let warmStart = clock.now
            let warmImage = await cache.image(for: reference, cacheNamespace: "baseline") { _ in
                XCTFail("warm cache lookup must not load bytes")
                return nil
            }
            XCTAssertNotNil(warmImage)
            warm.append(Self.nanoseconds(warmStart.duration(to: clock.now)))
        }

        let snapshot = await cache.diagnosticSnapshot()
        XCTAssertEqual(snapshot.entries, 4)
        XCTAssertEqual(snapshot.misses, 4)
        XCTAssertEqual(snapshot.hits, 4)
        XCTAssertGreaterThan(snapshot.costBytes, 0)

        let coldSummary = PerformanceSampleSummary(nanoseconds: cold)
        let warmSummary = PerformanceSampleSummary(nanoseconds: warm)
        let downsampleSummary = PerformanceSampleSummary(nanoseconds: downsample)
        let result = "ImageStressBaseline fixture=\(PerformanceBaselineFixtures.identity) entries=\(snapshot.entries) costBytes=\(snapshot.costBytes) hits=\(snapshot.hits) misses=\(snapshot.misses) coldMedianMs=\(coldSummary.medianMilliseconds) coldP95Ms=\(coldSummary.p95Milliseconds) warmMedianMs=\(warmSummary.medianMilliseconds) warmP95Ms=\(warmSummary.p95Milliseconds) downsampleMedianMs=\(downsampleSummary.medianMilliseconds) downsampleP95Ms=\(downsampleSummary.p95Milliseconds)"
        print("[PERF] \(result)")
        XCTContext.runActivity(named: result) { _ in }
    }

    @MainActor
    func testCacheWriteAndOpenBaseline() async throws {
        guard ProcessInfo.processInfo.environment["HERMEX_RUN_PERFORMANCE_BASELINES"] == "1" else {
            throw XCTSkip("Set HERMEX_RUN_PERFORMANCE_BASELINES=1 for the repeated 50/500/5000 cache baseline.")
        }

        for messageCount in [50, 500, 5_000] {
            let server = try XCTUnwrap(URL(string: "https://performance.example.invalid"))
            let sessionID = "synthetic-cache-session-\(messageCount)"
            let messages = PerformanceBaselineFixtures.cachedMessages(count: messageCount)
            let sessions = try PerformanceBaselineFixtures.sessionList()

            let clock = ContinuousClock()
            var coldWrites: [UInt64] = []
            var warmWrites: [UInt64] = []
            var lastDiagnostic = CacheWriteDiagnosticSnapshot()
            var retainedContainer: ModelContainer?
            let iterations = PerformanceBaselineFixtures.warmupCount + PerformanceBaselineFixtures.sampleCount
            for iteration in 0..<iterations {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(
                    for: CachedSession.self,
                    CachedMessage.self,
                    configurations: configuration
                )
                let coldContext = ModelContext(container)
                try CacheStore.cacheSessions(
                    sessions,
                    serverURL: server,
                    in: coldContext,
                    cachedAt: Date()
                )
                let coldStart = clock.now
                try CacheStore.cacheMessages(
                    messages,
                    serverURL: server,
                    sessionID: sessionID,
                    in: coldContext
                ) { lastDiagnostic = $0 }
                let coldDuration = Self.nanoseconds(coldStart.duration(to: clock.now))

                let warmStart = clock.now
                try CacheStore.cacheMessages(
                    messages,
                    serverURL: server,
                    sessionID: sessionID,
                    in: coldContext
                ) { lastDiagnostic = $0 }
                let warmDuration = Self.nanoseconds(warmStart.duration(to: clock.now))
                if iteration >= PerformanceBaselineFixtures.warmupCount {
                    coldWrites.append(coldDuration)
                    warmWrites.append(warmDuration)
                }
                retainedContainer = container
            }

            let container = try XCTUnwrap(retainedContainer)
            let newestLimit = min(50, messageCount)
            var coldOpen: [UInt64] = []
            var warmOpen: [UInt64] = []
            var offlineOpen: [UInt64] = []
            for iteration in 0..<iterations {
                let reader = TranscriptCacheReader(modelContainer: container)
                let openStart = clock.now
                let page = try await reader.cachedMessages(
                    serverURL: server,
                    sessionID: sessionID,
                    now: Date(),
                    newestLimit: newestLimit
                )
                XCTAssertEqual(page.messages.count, newestLimit)
                let coldElapsed = Self.nanoseconds(openStart.duration(to: clock.now))

                let warmStart = clock.now
                let warmPage = try await reader.cachedMessages(
                    serverURL: server,
                    sessionID: sessionID,
                    now: Date(),
                    newestLimit: newestLimit
                )
                XCTAssertEqual(warmPage.messages.count, newestLimit)
                let warmElapsed = Self.nanoseconds(warmStart.duration(to: clock.now))

                let offlineContext = ModelContext(container)
                let offlineStart = clock.now
                let offlineMessages = try CacheStore.cachedMessages(
                    serverURL: server,
                    sessionID: sessionID,
                    in: offlineContext,
                    newestLimit: newestLimit
                )
                XCTAssertEqual(offlineMessages.count, newestLimit)
                let offlineElapsed = Self.nanoseconds(offlineStart.duration(to: clock.now))
                if iteration >= PerformanceBaselineFixtures.warmupCount {
                    coldOpen.append(coldElapsed)
                    warmOpen.append(warmElapsed)
                    offlineOpen.append(offlineElapsed)
                }
            }

            let coldWriteSummary = PerformanceSampleSummary(nanoseconds: coldWrites)
            let warmWriteSummary = PerformanceSampleSummary(nanoseconds: warmWrites)
            let coldOpenSummary = PerformanceSampleSummary(nanoseconds: coldOpen)
            let warmOpenSummary = PerformanceSampleSummary(nanoseconds: warmOpen)
            let offlineOpenSummary = PerformanceSampleSummary(nanoseconds: offlineOpen)
            let result = "CacheBaseline fixture=\(PerformanceBaselineFixtures.identity) messages=\(messageCount) samples=\(PerformanceBaselineFixtures.sampleCount) coldWriteMedianMs=\(coldWriteSummary.medianMilliseconds) coldWriteP95Ms=\(coldWriteSummary.p95Milliseconds) warmWriteMedianMs=\(warmWriteSummary.medianMilliseconds) warmWriteP95Ms=\(warmWriteSummary.p95Milliseconds) coldOpenMedianMs=\(coldOpenSummary.medianMilliseconds) coldOpenP95Ms=\(coldOpenSummary.p95Milliseconds) warmOpenMedianMs=\(warmOpenSummary.medianMilliseconds) warmOpenP95Ms=\(warmOpenSummary.p95Milliseconds) offlineOpenMedianMs=\(offlineOpenSummary.medianMilliseconds) offlineOpenP95Ms=\(offlineOpenSummary.p95Milliseconds) fetches=\(lastDiagnostic.fetchCount) fetched=\(lastDiagnostic.objectsFetched) updated=\(lastDiagnostic.objectsUpdated) inserted=\(lastDiagnostic.objectsInserted) deleted=\(lastDiagnostic.objectsDeleted) maintenanceDeleted=\(lastDiagnostic.maintenanceDeleted) mainActor=\(lastDiagnostic.ranOnMainActor)"
            print("[PERF] \(result)")
            XCTContext.runActivity(named: result) { _ in }
        }
    }

    @MainActor
    func testCacheOpenBaseline() async throws {
        guard ProcessInfo.processInfo.environment["HERMEX_RUN_PERFORMANCE_BASELINES"] == "1" else {
            throw XCTSkip("Run with the HermesPerformanceBaselines scheme.")
        }

        for messageCount in [50, 500, 5_000] {
            let container = try ModelContainer(
                for: CachedSession.self,
                CachedMessage.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)
            let server = try XCTUnwrap(URL(string: "https://performance.example.invalid"))
            let sessionID = "synthetic-open-session-\(messageCount)"
            var coldWriteDiagnostic = CacheWriteDiagnosticSnapshot()
            try CacheStore.cacheMessages(
                PerformanceBaselineFixtures.cachedMessages(count: messageCount),
                serverURL: server,
                sessionID: sessionID,
                in: context
            ) { coldWriteDiagnostic = $0 }

            let newestLimit = min(messageCount, 50)
            let clock = ContinuousClock()
            var cold: [UInt64] = []
            var warm: [UInt64] = []
            var offline: [UInt64] = []
            let iterations = PerformanceBaselineFixtures.warmupCount + PerformanceBaselineFixtures.sampleCount
            for iteration in 0..<iterations {
                let reader = TranscriptCacheReader(modelContainer: container)
                let coldStart = clock.now
                let coldPage = try await reader.cachedMessages(
                    serverURL: server,
                    sessionID: sessionID,
                    now: Date(),
                    newestLimit: newestLimit
                )
                let coldElapsed = Self.nanoseconds(coldStart.duration(to: clock.now))

                let warmStart = clock.now
                let warmPage = try await reader.cachedMessages(
                    serverURL: server,
                    sessionID: sessionID,
                    now: Date(),
                    newestLimit: newestLimit
                )
                let warmElapsed = Self.nanoseconds(warmStart.duration(to: clock.now))

                let offlineStart = clock.now
                let offlineMessages = try CacheStore.cachedMessages(
                    serverURL: server,
                    sessionID: sessionID,
                    in: ModelContext(container),
                    newestLimit: newestLimit
                )
                let offlineElapsed = Self.nanoseconds(offlineStart.duration(to: clock.now))
                XCTAssertEqual(coldPage.messages.count, newestLimit)
                XCTAssertEqual(warmPage.messages.count, newestLimit)
                XCTAssertEqual(offlineMessages.count, newestLimit)

                if iteration >= PerformanceBaselineFixtures.warmupCount {
                    cold.append(coldElapsed)
                    warm.append(warmElapsed)
                    offline.append(offlineElapsed)
                }
            }

            let coldSummary = PerformanceSampleSummary(nanoseconds: cold)
            let warmSummary = PerformanceSampleSummary(nanoseconds: warm)
            let offlineSummary = PerformanceSampleSummary(nanoseconds: offline)
            let result = "CacheOpenBaseline fixture=\(PerformanceBaselineFixtures.identity) messages=\(messageCount) samples=\(PerformanceBaselineFixtures.sampleCount) coldMedianMs=\(coldSummary.medianMilliseconds) coldP95Ms=\(coldSummary.p95Milliseconds) warmMedianMs=\(warmSummary.medianMilliseconds) warmP95Ms=\(warmSummary.p95Milliseconds) offlineMedianMs=\(offlineSummary.medianMilliseconds) offlineP95Ms=\(offlineSummary.p95Milliseconds) coldWriteFetches=\(coldWriteDiagnostic.fetchCount) coldWriteFetched=\(coldWriteDiagnostic.objectsFetched) coldWriteInserted=\(coldWriteDiagnostic.objectsInserted) coldWriteUpdated=\(coldWriteDiagnostic.objectsUpdated) coldWriteDeleted=\(coldWriteDiagnostic.objectsDeleted) serverNetwork=false"
            print("[PERF] \(result)")
            XCTContext.runActivity(named: result) { _ in }
        }
    }

    private static func nanoseconds(_ duration: Duration) -> UInt64 {
        let components = duration.components
        return UInt64(max(components.seconds, 0)) * 1_000_000_000
            + UInt64(max(components.attoseconds, 0)) / 1_000_000_000
    }
}
