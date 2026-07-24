import Foundation

/// Pure helpers for pacing streamed assistant text at a word cadence (issue #212).
///
/// The streaming flush pipeline reveals buffered tokens word-by-word instead of
/// dumping whole burst batches into the transcript at once. A drainable "unit" is
/// one word plus its trailing whitespace; leading whitespace attaches to the first
/// unit, and a trailing in-progress word counts as a unit so buffers without
/// whitespace still drain. Splitting walks `Character`s (grapheme clusters), so
/// emoji/ZWJ sequences and combining marks are never split, and `head + tail`
/// always reproduces the input exactly — pacing can never alter final content.
enum StreamingWordDrain {
    /// Number of drainable word units in `text`.
    static func unitCount(in text: String) -> Int {
        var count = 0
        var hasSeenNonWhitespace = false
        var previousWasWhitespace = false
        for character in text {
            let isWhitespace = character.isWhitespace
            if count == 0 {
                count = 1
            } else if previousWasWhitespace, !isWhitespace, hasSeenNonWhitespace {
                count += 1
            }
            if !isWhitespace {
                hasSeenNonWhitespace = true
            }
            previousWasWhitespace = isWhitespace
        }
        return count
    }

    /// Splits `text` after its first `unitCount` units; `head + tail == text`.
    /// A non-positive count returns everything in `tail`; a count at or beyond
    /// the backlog returns everything in `head`.
    static func splitAtUnitBoundary(_ text: String, unitCount: Int) -> (head: String, tail: String) {
        guard unitCount > 0, !text.isEmpty else { return ("", text) }

        var unitsSeen = 0
        var hasSeenNonWhitespace = false
        var previousWasWhitespace = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let isWhitespace = character.isWhitespace
            if unitsSeen == 0 {
                unitsSeen = 1
            } else if previousWasWhitespace, !isWhitespace, hasSeenNonWhitespace {
                unitsSeen += 1
                if unitsSeen > unitCount {
                    return (String(text[..<index]), String(text[index...]))
                }
            }
            if !isWhitespace {
                hasSeenNonWhitespace = true
            }
            previousWasWhitespace = isWhitespace
            index = text.index(after: index)
        }
        return (text, "")
    }

    /// Units to drain on one cadence tick. Normally one word per tick; when the
    /// backlog would take longer than `maxLagNanoseconds` to drain at
    /// `cadenceNanoseconds` per word, the quota scales up proportionally so the
    /// display catches up to the live stream within the lag bound.
    static func drainQuota(
        backlogUnitCount: Int,
        cadenceNanoseconds: UInt64,
        maxLagNanoseconds: UInt64
    ) -> Int {
        guard backlogUnitCount > 1 else { return 1 }
        guard cadenceNanoseconds > 0, maxLagNanoseconds > 0 else { return backlogUnitCount }

        let drainNanoseconds = Double(backlogUnitCount) * Double(cadenceNanoseconds)
        let quota = Int((drainNanoseconds / Double(maxLagNanoseconds)).rounded(.up))
        return min(backlogUnitCount, max(1, quota))
    }
}

/// Chunked pending text for the paced streaming path.
///
/// Appends scan only the new chunk to maintain the drainable-unit count. A paced
/// drain joins only enough leading chunks to cross the requested word boundary;
/// the untouched tail remains chunked, so neither token arrival nor backlog
/// accounting copies the complete response. `StreamingWordDrain` still performs
/// the final split over a contiguous String, preserving its grapheme guarantees.
struct StreamingTextBuffer {
    private static let targetChunkCharacterCount = 2_048

    struct Drain {
        let text: String
        let copiedOrScannedCharacters: Int
    }

    private struct Chunk {
        var text: String
        var unitContribution: Int
        var characterCount: Int
    }

    private var chunks: [Chunk] = []
    private var headIndex = 0
    private var hasSeenNonWhitespace = false
    private var previousWasWhitespace = false

    private(set) var unitCount = 0

    var isEmpty: Bool { headIndex >= chunks.count }
    var chunkCount: Int { chunks.count - headIndex }
    var maximumChunkCharacterCount: Int {
        chunks[headIndex...].map(\.characterCount).max() ?? 0
    }

    /// Adds a token and returns the number of newly scanned Characters.
    @discardableResult
    mutating func append(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var scanned = 0
        var pieceStart = text.startIndex
        var pieceCharacterCount = 0
        var pieceStartUnitCount = unitCount
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            scanned += 1
            pieceCharacterCount += 1
            let isWhitespace = character.isWhitespace
            if unitCount == 0 {
                unitCount = 1
            } else if previousWasWhitespace, !isWhitespace, hasSeenNonWhitespace {
                unitCount += 1
            }
            if !isWhitespace {
                hasSeenNonWhitespace = true
            }
            previousWasWhitespace = isWhitespace

            let nextIndex = text.index(after: index)
            if pieceCharacterCount == Self.targetChunkCharacterCount {
                appendStorageChunk(
                    String(text[pieceStart..<nextIndex]),
                    characterCount: pieceCharacterCount,
                    unitContribution: unitCount - pieceStartUnitCount
                )
                pieceStart = nextIndex
                pieceCharacterCount = 0
                pieceStartUnitCount = unitCount
            }
            index = nextIndex
        }

        if pieceStart < text.endIndex {
            appendStorageChunk(
                String(text[pieceStart...]),
                characterCount: pieceCharacterCount,
                unitContribution: unitCount - pieceStartUnitCount
            )
        }
        return scanned
    }

    private mutating func appendStorageChunk(
        _ text: String,
        characterCount: Int,
        unitContribution: Int
    ) {
        if !isEmpty,
           chunks[chunks.count - 1].characterCount + characterCount <= Self.targetChunkCharacterCount {
            chunks[chunks.count - 1].text.append(contentsOf: text)
            chunks[chunks.count - 1].unitContribution += unitContribution
            chunks[chunks.count - 1].characterCount += characterCount
        } else {
            chunks.append(
                Chunk(
                    text: text,
                    unitContribution: unitContribution,
                    characterCount: characterCount
                )
            )
        }
    }

    /// Materializes all pending text only for reconnect replay comparison.
    func replayContent() -> String {
        guard !isEmpty else { return "" }
        return chunks[headIndex...].map(\.text).joined()
    }

    /// Drains at most `maxUnitCount` word units, or everything when nil.
    mutating func drain(maxUnitCount: Int? = nil) -> Drain {
        guard !isEmpty else { return Drain(text: "", copiedOrScannedCharacters: 0) }

        guard let maxUnitCount, maxUnitCount < unitCount else {
            let activeChunks = chunks[headIndex...]
            let text = activeChunks.map(\.text).joined()
            let volume = activeChunks.reduce(into: 0) { $0 += $1.characterCount }
            reset()
            return Drain(text: text, copiedOrScannedCharacters: volume)
        }
        guard maxUnitCount > 0 else {
            return Drain(text: "", copiedOrScannedCharacters: 0)
        }

        var selectedChunks: [String] = []
        var selectedCharacterCount = 0
        var selectedUnitCount = 0
        var cursor = headIndex

        while cursor < chunks.count, selectedUnitCount <= maxUnitCount {
            let chunk = chunks[cursor]
            selectedChunks.append(chunk.text)
            selectedCharacterCount += chunk.characterCount
            selectedUnitCount += chunk.unitContribution
            cursor += 1
        }

        let candidate = selectedChunks.joined()
        let split = StreamingWordDrain.splitAtUnitBoundary(candidate, unitCount: maxUnitCount)
        guard !split.head.isEmpty else {
            return Drain(text: "", copiedOrScannedCharacters: selectedCharacterCount)
        }

        if split.tail.isEmpty {
            headIndex = cursor
        } else {
            let tailCharacterCount = split.tail.count
            chunks[cursor - 1] = Chunk(
                text: split.tail,
                unitContribution: selectedUnitCount - maxUnitCount,
                characterCount: tailCharacterCount
            )
            headIndex = cursor - 1
        }
        unitCount -= maxUnitCount
        compactStorageIfNeeded()
        return Drain(
            text: split.head,
            copiedOrScannedCharacters: selectedCharacterCount * 2
        )
    }

    mutating func reset() {
        chunks.removeAll(keepingCapacity: true)
        headIndex = 0
        unitCount = 0
        hasSeenNonWhitespace = false
        previousWasWhitespace = false
    }

    private mutating func compactStorageIfNeeded() {
        guard headIndex >= 64, headIndex * 2 >= chunks.count else { return }
        chunks.removeFirst(headIndex)
        headIndex = 0
    }
}
