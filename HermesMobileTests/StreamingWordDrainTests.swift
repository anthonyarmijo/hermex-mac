import XCTest
@testable import HermesMobile

final class StreamingWordDrainTests: XCTestCase {
    // MARK: - unitCount

    func testUnitCountEmptyTextIsZero() {
        XCTAssertEqual(StreamingWordDrain.unitCount(in: ""), 0)
    }

    func testUnitCountTextWithoutWhitespaceIsOneUnit() {
        XCTAssertEqual(StreamingWordDrain.unitCount(in: "chunk-0chunk-1chunk-2"), 1)
    }

    func testUnitCountWhitespaceOnlyTextIsOneUnit() {
        XCTAssertEqual(StreamingWordDrain.unitCount(in: "  \n\t "), 1)
    }

    func testUnitCountCountsWordsWithTrailingWhitespace() {
        XCTAssertEqual(StreamingWordDrain.unitCount(in: "alpha beta gamma"), 3)
        XCTAssertEqual(StreamingWordDrain.unitCount(in: "alpha beta gamma "), 3)
    }

    func testUnitCountLeadingWhitespaceAttachesToFirstUnit() {
        XCTAssertEqual(StreamingWordDrain.unitCount(in: "  alpha beta"), 2)
    }

    func testUnitCountTreatsConsecutiveWhitespaceAsOneSeparator() {
        XCTAssertEqual(StreamingWordDrain.unitCount(in: "alpha  \n\n beta\t\tgamma"), 3)
    }

    func testUnitCountHandlesGraphemeClusters() {
        XCTAssertEqual(StreamingWordDrain.unitCount(in: "👩‍👩‍👧‍👦 🇫🇷 café"), 3)
    }

    // MARK: - splitAtUnitBoundary

    func testSplitAtUnitBoundaryRoundTripsForEveryCount() {
        let text = "  alpha beta\n\ngamma  delta epsilon"
        let unitCount = StreamingWordDrain.unitCount(in: text)
        for count in 0...(unitCount + 2) {
            let (head, tail) = StreamingWordDrain.splitAtUnitBoundary(text, unitCount: count)
            XCTAssertEqual(head + tail, text, "head + tail must reproduce input for count \(count)")
        }
    }

    func testSplitAtUnitBoundaryZeroCountReturnsEverythingInTail() {
        let (head, tail) = StreamingWordDrain.splitAtUnitBoundary("alpha beta", unitCount: 0)
        XCTAssertEqual(head, "")
        XCTAssertEqual(tail, "alpha beta")
    }

    func testSplitAtUnitBoundaryTakesWordsWithTrailingWhitespace() {
        let (head, tail) = StreamingWordDrain.splitAtUnitBoundary("alpha  beta gamma", unitCount: 1)
        XCTAssertEqual(head, "alpha  ")
        XCTAssertEqual(tail, "beta gamma")
    }

    func testSplitAtUnitBoundaryCountBeyondBacklogReturnsEverythingInHead() {
        let (head, tail) = StreamingWordDrain.splitAtUnitBoundary("alpha beta", unitCount: 5)
        XCTAssertEqual(head, "alpha beta")
        XCTAssertEqual(tail, "")
    }

    func testSplitAtUnitBoundaryNeverSplitsGraphemeClusters() {
        let (head, tail) = StreamingWordDrain.splitAtUnitBoundary("👩‍👩‍👧‍👦 x", unitCount: 1)
        XCTAssertEqual(head, "👩‍👩‍👧‍👦 ")
        XCTAssertEqual(tail, "x")
    }

    func testSplitAtUnitBoundaryKeepsCombiningMarksWithBaseCharacter() {
        // "e" + U+0301 combine into one grapheme; the boundary after "café" must
        // include the combining mark in head.
        let text = "cafe\u{301} au lait"
        let (head, tail) = StreamingWordDrain.splitAtUnitBoundary(text, unitCount: 1)
        XCTAssertEqual(head, "cafe\u{301} ")
        XCTAssertEqual(tail, "au lait")
    }

    func testSplitAtUnitBoundaryLeadingWhitespaceStaysWithFirstUnit() {
        let (head, tail) = StreamingWordDrain.splitAtUnitBoundary("  alpha beta", unitCount: 1)
        XCTAssertEqual(head, "  alpha ")
        XCTAssertEqual(tail, "beta")
    }

    // MARK: - drainQuota

    func testDrainQuotaSmallBacklogDrainsOneWordPerTick() {
        // 10 words × 48ms = 480ms, under the 1s lag bound → steady cadence.
        XCTAssertEqual(
            StreamingWordDrain.drainQuota(
                backlogUnitCount: 10,
                cadenceNanoseconds: 48_000_000,
                maxLagNanoseconds: 1_000_000_000
            ),
            1
        )
    }

    func testDrainQuotaScalesWithBacklogToStayWithinLagBound() {
        // 1000 words × 48ms = 48s of backlog; quota must scale to drain in ~1s.
        let quota = StreamingWordDrain.drainQuota(
            backlogUnitCount: 1000,
            cadenceNanoseconds: 48_000_000,
            maxLagNanoseconds: 1_000_000_000
        )
        XCTAssertEqual(quota, 48)
    }

    func testDrainQuotaNeverExceedsBacklog() {
        let quota = StreamingWordDrain.drainQuota(
            backlogUnitCount: 5,
            cadenceNanoseconds: 1_000_000_000,
            maxLagNanoseconds: 1_000_000
        )
        XCTAssertEqual(quota, 5)
    }

    func testDrainQuotaSingleUnitBacklogIsOne() {
        XCTAssertEqual(
            StreamingWordDrain.drainQuota(
                backlogUnitCount: 1,
                cadenceNanoseconds: 48_000_000,
                maxLagNanoseconds: 1_000_000_000
            ),
            1
        )
    }

    func testDrainQuotaZeroCadenceDrainsEverything() {
        XCTAssertEqual(
            StreamingWordDrain.drainQuota(
                backlogUnitCount: 7,
                cadenceNanoseconds: 0,
                maxLagNanoseconds: 1_000_000_000
            ),
            7
        )
    }

    func testDrainQuotaZeroLagBoundDrainsEverything() {
        XCTAssertEqual(
            StreamingWordDrain.drainQuota(
                backlogUnitCount: 7,
                cadenceNanoseconds: 48_000_000,
                maxLagNanoseconds: 0
            ),
            7
        )
    }

    // MARK: - StreamingTextBuffer

    func testStreamingTextBufferIncrementalUnitCountMatchesJoinedText() {
        let chunks = [
            "  cafe",
            "\u{301}",
            "  👩‍👩‍👧‍👦",
            "\r",
            "\n",
            "tabs\t",
            "and  spaces"
        ]
        var buffer = StreamingTextBuffer()
        var joined = ""

        for chunk in chunks {
            buffer.append(chunk)
            joined += chunk
            XCTAssertEqual(buffer.unitCount, StreamingWordDrain.unitCount(in: joined))
            XCTAssertEqual(buffer.replayContent(), joined)
        }
    }

    func testStreamingTextBufferDrainsEveryUnitByteIdentically() {
        let chunks = [
            "The 👩‍👩‍👧‍👦 family ",
            "and 🇫🇷 flag met.\r",
            "\ntabs\tand  doubles ",
            "cafe",
            "\u{301} fin"
        ]
        let expected = chunks.joined()
        var buffer = StreamingTextBuffer()
        chunks.forEach { buffer.append($0) }

        var drained = ""
        while !buffer.isEmpty {
            drained += buffer.drain(maxUnitCount: 1).text
        }

        XCTAssertEqual(Array(drained.utf8), Array(expected.utf8))
        XCTAssertEqual(buffer.unitCount, 0)
        XCTAssertEqual(buffer.chunkCount, 0)
    }

    func testStreamingTextBufferBoundedDrainLeavesExactReplayTail() {
        var buffer = StreamingTextBuffer()
        ["alpha ", "beta gamma ", "delta"].forEach { buffer.append($0) }

        let first = buffer.drain(maxUnitCount: 2)

        XCTAssertEqual(first.text, "alpha beta ")
        XCTAssertEqual(buffer.replayContent(), "gamma delta")
        XCTAssertEqual(buffer.unitCount, 2)
        XCTAssertEqual(buffer.drain().text, "gamma delta")
        XCTAssertTrue(buffer.isEmpty)
    }

    func testStreamingTextBufferResetDropsReplayAndUnitState() {
        var buffer = StreamingTextBuffer()
        buffer.append("alpha beta ")
        buffer.reset()
        buffer.append("  gamma")

        XCTAssertEqual(buffer.replayContent(), "  gamma")
        XCTAssertEqual(buffer.unitCount, 1)
    }

    func testStreamingTextBufferCoalescesTinyTokensIntoBoundedChunks() {
        var buffer = StreamingTextBuffer()
        for _ in 0..<1_000 {
            buffer.append("word ")
        }

        XCTAssertGreaterThan(buffer.chunkCount, 1)
        XCTAssertLessThan(buffer.chunkCount, 10)
        XCTAssertEqual(buffer.unitCount, 1_000)
        XCTAssertEqual(buffer.replayContent(), String(repeating: "word ", count: 1_000))
    }

    func testStreamingTextBufferSplitsOneOversizedTokenIntoBoundedChunks() {
        let token = String(repeating: "word ", count: 5_000)
        var buffer = StreamingTextBuffer()

        buffer.append(token)

        XCTAssertGreaterThan(buffer.chunkCount, 1)
        XCTAssertLessThanOrEqual(buffer.maximumChunkCharacterCount, 2_048)
        XCTAssertEqual(buffer.unitCount, 5_000)
        XCTAssertEqual(buffer.replayContent(), token)
        XCTAssertEqual(buffer.drain().text, token)
    }
}
