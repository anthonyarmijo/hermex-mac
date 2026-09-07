import XCTest
@testable import HermesMobile

/// Guards the memoized markdown layout used by the transcript renderers.
///
/// The optimization it protects: for content with no display math, the renderer
/// used to segment the whole string and then run `replacingInlineMath` over the
/// whole string a second time, on every SwiftUI body evaluation. These tests
/// pin the two properties that make dropping that second pass safe — the cached
/// layout must be byte-identical to the old two-pass output, and the streaming
/// path must not pollute the cache.
final class MarkdownMathLayoutCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MarkdownMathLayoutCache.removeAll()
    }

    override func tearDown() {
        MarkdownMathLayoutCache.removeAll()
        super.tearDown()
    }

    /// The load-bearing equivalence: `.plain` must equal what the old
    /// `replacingInlineMath(in:)` pass produced, or rendering changed.
    func testPlainLayoutMatchesLegacyInlineMathPass() {
        let inputs = [
            "plain prose with no math at all",
            "**bold** and _italic_ and `code`",
            "a [link](https://example.com) and text",
            "money: costs $5 today and $7 tomorrow",
            #"inline math: $x^2 + y^2 = z^2$ inside prose"#,
            "```swift\nlet a = 1\n```",
            "list:\n- one\n- two\n\n1. first\n2. second",
            "> quote\n> continued",
            "| a | b |\n|---|---|\n| 1 | 2 |",
            "unicode: café — ünïcödé 😀 中文",
            "ab",
            ""
        ]

        for input in inputs {
            guard case .plain(let layout) = MarkdownMathLayoutCache.layout(for: input) else {
                continue
            }
            XCTAssertEqual(
                layout,
                MarkdownMathFormatter.replacingInlineMath(in: input),
                "Cached plain layout diverged from the legacy pass for \(input.debugDescription)"
            )
        }
    }

    func testDisplayMathStillSegments() {
        guard case .segmented(let segments) = MarkdownMathLayoutCache.layout(for: "before $$x = 1$$ after") else {
            return XCTFail("Expected display math to produce a segmented layout.")
        }

        XCTAssertTrue(segments.containsMath)
        XCTAssertEqual(segments, MarkdownMathSegmenter.segments(in: "before $$x = 1$$ after"))
    }

    func testRepeatedLayoutRequestsReturnEqualResults() {
        let content = "an answer with **bold** and `code` and no math"

        let first = MarkdownMathLayoutCache.layout(for: content)
        let second = MarkdownMathLayoutCache.layout(for: content)

        XCTAssertEqual(first, second)
    }

    /// Streaming mutates the string on nearly every token. If that path wrote
    /// through the cache it would insert an entry per token and evict the
    /// settled answers the cache exists to protect.
    func testUncachedLayoutDoesNotPopulateTheCache() {
        let content = "streaming answer with no math"

        // Comparing the two layout values proves nothing: they are equal
        // whether or not the cache was written. Observe the cache directly.
        XCTAssertFalse(MarkdownMathLayoutCache.hasCachedLayout(for: content))

        let uncached = MarkdownMathLayoutCache.uncachedLayout(for: content)

        XCTAssertFalse(
            MarkdownMathLayoutCache.hasCachedLayout(for: content),
            "The streaming path must not write to the cache; per-token entries would evict settled answers."
        )

        let cached = MarkdownMathLayoutCache.layout(for: content)

        XCTAssertTrue(
            MarkdownMathLayoutCache.hasCachedLayout(for: content),
            "The settled path is expected to memoize."
        )
        XCTAssertEqual(uncached, cached, "Cached and uncached layouts must agree.")
    }

    func testEmptyAndShortContentStaysStable() {
        XCTAssertEqual(
            MarkdownMathLayoutCache.layout(for: ""),
            MarkdownMathLayoutCache.layout(for: "")
        )
        XCTAssertEqual(
            MarkdownMathLayoutCache.layout(for: "a"),
            MarkdownMathLayoutCache.layout(for: "a")
        )
    }

    /// Differential check over generated content: for every no-math input, the
    /// cached `.plain` payload must equal the legacy two-pass output exactly.
    ///
    /// This is the test that actually licenses dropping the second
    /// `replacingInlineMath` pass. It is randomized but seeded, so a failure is
    /// reproducible from the printed input.
    func testPlainLayoutMatchesLegacyPassAcrossGeneratedContent() {
        let fragments = [
            "prose ", "**bold** ", "`code` ", "$5 ", "$x^2$ ", "\\$escaped ",
            "\n\n", "- item\n", "> quote\n", "café ", "| a | b |\n", "[l](u) ",
            "```\ncode\n```\n", "# heading\n", "1. ordered\n",
            // Display delimiters, including the empty spans the segmenter
            // recognises but emits no math for. These are the cases that
            // regressed once; keep them in the generator.
            "$$ $$ ", "$$$$ ", "\\[ \\] ", "$$m$$ ", "\\[d\\] ", "$$", "\\["
        ]

        var generator = SeededGenerator(seed: 0xC0FFEE)
        var checked = 0

        for _ in 0..<3_000 {
            let count = Int.random(in: 1...14, using: &generator)
            var content = ""
            for _ in 0..<count {
                content += fragments.randomElement(using: &generator)!
            }

            MarkdownMathLayoutCache.removeAll()
            guard case .plain(let layout) = MarkdownMathLayoutCache.layout(for: content) else {
                continue
            }
            checked += 1

            XCTAssertEqual(
                layout,
                MarkdownMathFormatter.replacingInlineMath(in: content),
                "Layout diverged from the legacy pass for \(content.debugDescription)"
            )
        }

        XCTAssertGreaterThan(checked, 500, "Generator produced too few no-math cases to be meaningful.")
    }

    /// A display-math span whose body is empty or whitespace-only produces no
    /// `.displayMath` segment, but the segmenter has still consumed the
    /// delimiters. Reconstructing the plain layout by joining the remaining
    /// markdown would silently swallow that literal text.
    ///
    /// Caught in review on #261 — the original generator never produced an
    /// empty span, so nothing failed. The leading-delimiter case matters
    /// specifically because it still leaves exactly one markdown segment, so a
    /// segment-count check does not catch it.
    func testEmptyDisplayMathSpansSurviveAsLiteralText() {
        let inputs = [
            "before $$ $$ after",
            "before $$$$ after",
            "before $$\n\n$$ after",
            #"before \[ \] after"#,
            "text $$   $$ more text",
            "$$ $$",
            "$$ $$ trailing",
            #"\[ \] leading"#
        ]

        for input in inputs {
            guard case .plain(let layout) = MarkdownMathLayoutCache.layout(for: input) else {
                continue
            }
            XCTAssertEqual(
                layout,
                MarkdownMathFormatter.replacingInlineMath(in: input),
                "Empty display-math delimiters were dropped for \(input.debugDescription)"
            )
        }
    }
}

/// Deterministic generator so a differential failure is reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
