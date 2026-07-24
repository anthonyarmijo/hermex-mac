import SwiftData
import XCTest
@testable import HermesMobile

@MainActor
enum TestCacheStore {
    @discardableResult
    static func cacheSessions(
        _ sessions: [SessionSummary],
        serverURL: URL,
        in context: ModelContext,
        cachedAt: Date = Date()
    ) async throws -> CacheWriteDiagnosticSnapshot {
        let writer = CacheWriter(modelContainer: context.container)
        let generation = UUID()
        await writer.activate(
            scope: .sessions(serverURLString: serverURL.absoluteString),
            generation: generation
        )
        return try await writer.write(.replaceSessions(CacheSessionListSnapshot(
            serverURL: serverURL,
            sessions: sessions,
            cachedAt: cachedAt,
            generation: generation
        )))
    }

    @discardableResult
    static func cacheSession(
        _ session: SessionSummary,
        serverURL: URL,
        in context: ModelContext,
        cachedAt: Date = Date()
    ) async throws -> CacheWriteDiagnosticSnapshot {
        let writer = CacheWriter(modelContainer: context.container)
        return try await writer.write(.upsertSession(CacheSessionSnapshot(
            serverURL: serverURL,
            session: session,
            cachedAt: cachedAt,
            generation: UUID()
        )))
    }

    @discardableResult
    static func cacheMessages(
        _ messages: [ChatMessage],
        serverURL: URL,
        sessionID: String,
        in context: ModelContext,
        cachedAt: Date = Date(),
        diagnostics: ((CacheWriteDiagnosticSnapshot) -> Void)? = nil
    ) async throws -> CacheWriteDiagnosticSnapshot {
        let writer = CacheWriter(modelContainer: context.container)
        let generation = UUID()
        await writer.activate(
            scope: .messages(serverURLString: serverURL.absoluteString, sessionID: sessionID),
            generation: generation
        )
        let diagnostic = try await writer.write(.replaceMessages(CacheMessageListSnapshot(
            serverURL: serverURL,
            sessionID: sessionID,
            messages: messages,
            cachedAt: cachedAt,
            generation: generation
        )))
        diagnostics?(diagnostic)
        return diagnostic
    }

    static func clearAll(in context: ModelContext) async throws {
        let writer = CacheWriter(modelContainer: context.container)
        _ = try await writer.write(.clearAll)
    }

    static func clearCache(for serverURL: URL, in context: ModelContext) async throws {
        let writer = CacheWriter(modelContainer: context.container)
        _ = try await writer.write(.clearServer(serverURLString: serverURL.absoluteString))
    }

    @discardableResult
    static func performMaintenance(in context: ModelContext, now: Date) async throws -> CacheWriteDiagnosticSnapshot {
        let writer = CacheWriter(modelContainer: context.container)
        return try await writer.write(.maintenance(now: now))
    }
}

@MainActor
final class CacheStoreTests: XCTestCase {
    func testCacheSessionsWritesVisibleSessionsAndRemovesStaleEntries() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let firstCachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let secondCachedAt = Date(timeIntervalSince1970: 1_770_000_100)

        let firstResponse = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "keep", "title": "Planning", "last_message_at": 1770000000, "archived": false},
            {"session_id": "stale", "title": "Old thread", "last_message_at": 1760000000, "archived": false},
            {"session_id": "archived", "title": "Archived thread", "archived": true},
            {"title": "Missing ID", "archived": false}
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(firstResponse.sessions),
            serverURL: serverURL,
            in: context,
            cachedAt: firstCachedAt
        )

        var cachedSessions = try fetchCachedSessions(in: context)
        XCTAssertEqual(cachedSessions.map(\.sessionID).sorted(), ["keep", "stale"])
        XCTAssertEqual(cachedSessions.first(where: { $0.sessionID == "keep" })?.expiresAt, firstCachedAt.addingTimeInterval(CachePolicy.ttl))

        let secondResponse = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "keep", "title": "Updated planning", "last_message_at": 1770000100, "archived": false},
            {"session_id": "new", "title": "New thread", "last_message_at": 1770000200, "archived": false}
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(secondResponse.sessions),
            serverURL: serverURL,
            in: context,
            cachedAt: secondCachedAt
        )

        cachedSessions = try fetchCachedSessions(in: context)
        XCTAssertEqual(cachedSessions.map(\.sessionID).sorted(), ["keep", "new"])

        let updatedSession = try XCTUnwrap(cachedSessions.first { $0.sessionID == "keep" })
        XCTAssertEqual(updatedSession.title, "Updated planning")
        XCTAssertEqual(updatedSession.lastMessageAt, 1_770_000_100)
        XCTAssertEqual(updatedSession.cachedAt, secondCachedAt)
        XCTAssertEqual(updatedSession.expiresAt, secondCachedAt.addingTimeInterval(CachePolicy.ttl))
    }

    func testCachedSessionsPreserveSubagentClassificationAndReadOnlySafety() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let now = cachedAt.addingTimeInterval(60)
        let response = try decodeSessions("""
        {
          "sessions": [
            {
              "session_id": "subagent-child",
              "title": "Delegated research",
              "source_tag": "subagent",
              "raw_source": "subagent",
              "session_source": "other",
              "source_label": "Subagent",
              "parent_session_id": "parent-1",
              "relationship_type": "child_session",
              "read_only": true,
              "archived": false
            }
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(response.sessions),
            serverURL: serverURL,
            in: context,
            cachedAt: cachedAt
        )

        let cached = try XCTUnwrap(
            CacheStore.cachedSessions(serverURL: serverURL, in: context, now: now).first
        )
        XCTAssertEqual(cached.rawSource, "subagent")
        XCTAssertEqual(cached.parentSessionId, "parent-1")
        XCTAssertEqual(cached.relationshipType, "child_session")
        XCTAssertTrue(cached.isDelegatedSubagentSession)
        XCTAssertTrue(cached.isSessionReadOnly)
        XCTAssertFalse(AutomatedSessionVisibility(showsCron: true, showsCli: true).shows(cached))
        XCTAssertTrue(AutomatedSessionVisibility.showAll.shows(cached))
    }

    func testCachedSessionsPreserveClaudeCodeClassificationAndVisibility() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let response = try decodeSessions("""
        {
          "sessions": [
            {
              "session_id": "claude-code",
              "title": "Imported transcript",
              "source_tag": "claude_code",
              "raw_source": "claude_code",
              "is_cli_session": true,
              "read_only": true,
              "archived": false
            },
            {
              "session_id": "ordinary-cli",
              "title": "Terminal chat",
              "source_tag": "cli",
              "is_cli_session": true,
              "archived": false
            }
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(response.sessions),
            serverURL: serverURL,
            in: context,
            cachedAt: cachedAt
        )

        let cached = try CacheStore.cachedSessions(
            serverURL: serverURL,
            in: context,
            now: cachedAt.addingTimeInterval(60)
        )
        let hidden = AutomatedSessionVisibility(
            showsCron: true,
            showsCli: true,
            showsClaudeCode: false
        )

        XCTAssertTrue(try XCTUnwrap(cached.first { $0.sessionId == "claude-code" }).isClaudeCodeSession)
        XCTAssertEqual(cached.filter(hidden.shows).compactMap(\.sessionId), ["ordinary-cli"])
    }

    func testCacheMessagesWritesLoadedWindowAndRemovesStaleMessages() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let firstCachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let secondCachedAt = Date(timeIntervalSince1970: 1_770_000_100)
        let firstMessages = [
            ChatMessage(
                role: "user",
                content: "Hello",
                timestamp: 1_770_000_000,
                messageId: "m1"
            ),
            ChatMessage(
                role: "assistant",
                content: "Hi",
                timestamp: 1_770_000_001,
                messageId: "m2",
                reasoning: "Greet the user."
            )
        ]

        try await TestCacheStore.cacheMessages(
            firstMessages,
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            cachedAt: firstCachedAt
        )

        var cachedMessages = try fetchCachedMessages(in: context)
        XCTAssertEqual(cachedMessages.compactMap(\.messageId).sorted(), ["m1", "m2"])
        XCTAssertEqual(cachedMessages.first(where: { $0.messageId == "m2" })?.reasoning, "Greet the user.")
        XCTAssertEqual(cachedMessages.first(where: { $0.messageId == "m1" })?.expiresAt, firstCachedAt.addingTimeInterval(CachePolicy.ttl))

        let secondMessages = [
            ChatMessage(
                role: "assistant",
                content: "Updated hi",
                timestamp: 1_770_000_002,
                messageId: "m2",
                reasoning: "Updated reasoning."
            ),
            ChatMessage(
                role: "user",
                content: "Next",
                timestamp: 1_770_000_003,
                messageId: "m3"
            )
        ]

        try await TestCacheStore.cacheMessages(
            secondMessages,
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            cachedAt: secondCachedAt
        )

        cachedMessages = try fetchCachedMessages(in: context)
        XCTAssertEqual(cachedMessages.compactMap(\.messageId).sorted(), ["m2", "m3"])

        let updatedMessage = try XCTUnwrap(cachedMessages.first { $0.messageId == "m2" })
        XCTAssertEqual(updatedMessage.content, "Updated hi")
        XCTAssertEqual(updatedMessage.sortIndex, 0)
        XCTAssertEqual(updatedMessage.cachedAt, secondCachedAt)
        XCTAssertEqual(updatedMessage.expiresAt, secondCachedAt.addingTimeInterval(CachePolicy.ttl))
    }

    func testCacheSessionUpsertsOneSessionWithoutRemovingExistingSessions() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let firstCachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let secondCachedAt = Date(timeIntervalSince1970: 1_770_000_100)

        let existingResponse = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "existing", "title": "Existing", "last_message_at": 1770000000, "archived": false}
          ]
        }
        """)
        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(existingResponse.sessions),
            serverURL: serverURL,
            in: context,
            cachedAt: firstCachedAt
        )

        let forkResponse = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "fork", "title": "Existing (fork)", "last_message_at": 1770000100, "archived": false}
          ]
        }
        """)
        let fork = try XCTUnwrap(forkResponse.sessions?.first)

        try await TestCacheStore.cacheSession(
            fork,
            serverURL: serverURL,
            in: context,
            cachedAt: secondCachedAt
        )

        let cachedSessions = try fetchCachedSessions(in: context)
        XCTAssertEqual(cachedSessions.map(\.sessionID).sorted(), ["existing", "fork"])

        let forkedSession = try XCTUnwrap(cachedSessions.first { $0.sessionID == "fork" })
        XCTAssertEqual(forkedSession.title, "Existing (fork)")
        XCTAssertEqual(forkedSession.cachedAt, secondCachedAt)
    }

    func testCachedSessionsReturnsOnlyUnexpiredVisibleSessionsForServer() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let otherServerURL = URL(string: "https://other.example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let now = cachedAt.addingTimeInterval(60)

        let response = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "fresh", "title": "Fresh thread", "last_message_at": 1770000000, "archived": false},
            {"session_id": "archived", "title": "Archived thread", "archived": true}
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(response.sessions),
            serverURL: serverURL,
            in: context,
            cachedAt: cachedAt
        )

        let otherResponse = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "other", "title": "Other server", "last_message_at": 1770000100, "archived": false}
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(otherResponse.sessions),
            serverURL: otherServerURL,
            in: context,
            cachedAt: cachedAt
        )

        let cachedSessions = try CacheStore.cachedSessions(serverURL: serverURL, in: context, now: now)

        XCTAssertEqual(cachedSessions.map(\.sessionId), ["fresh"])
        XCTAssertEqual(cachedSessions.first?.title, "Fresh thread")
    }

    func testCachedSessionsIgnoresExpiredSessions() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let expiredNow = cachedAt.addingTimeInterval(CachePolicy.ttl + 1)
        let response = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "expired", "title": "Expired thread", "last_message_at": 1770000000, "archived": false}
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(response.sessions),
            serverURL: serverURL,
            in: context,
            cachedAt: cachedAt
        )

        let cachedSessions = try CacheStore.cachedSessions(serverURL: serverURL, in: context, now: expiredNow)

        XCTAssertTrue(cachedSessions.isEmpty)
    }

    func testCachedMessagesReturnsUnexpiredMessagesInStoredOrderForSession() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let now = cachedAt.addingTimeInterval(60)
        let messages = [
            ChatMessage(
                role: "assistant",
                content: "Second",
                timestamp: 1_770_000_002,
                messageId: "m2",
                reasoning: "Cached reasoning."
            ),
            ChatMessage(
                role: "user",
                content: "First",
                timestamp: 1_770_000_001,
                messageId: "m1"
            )
        ]

        try await TestCacheStore.cacheMessages(
            messages,
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            cachedAt: cachedAt
        )

        try await TestCacheStore.cacheMessages(
            [
                ChatMessage(
                    role: "user",
                    content: "Other session",
                    timestamp: 1_770_000_003,
                    messageId: "other"
                )
            ],
            serverURL: serverURL,
            sessionID: "other-session",
            in: context,
            cachedAt: cachedAt
        )

        let cachedMessages = try CacheStore.cachedMessages(
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            now: now
        )

        XCTAssertEqual(cachedMessages.map(\.messageId), ["m2", "m1"])
        XCTAssertEqual(cachedMessages.first?.reasoning, "Cached reasoning.")
    }

    func testCachedMessagesNewestLimitReturnsNewestPageInAscendingOrderWithoutDeletingHistory() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let messages = (0..<75).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "Message \(index)",
                timestamp: 1_770_000_000 + Double(index),
                messageId: "m\(index)"
            )
        }

        try await TestCacheStore.cacheMessages(
            messages,
            serverURL: serverURL,
            sessionID: "long-session",
            in: context,
            cachedAt: cachedAt
        )

        let newestPage = try CacheStore.cachedMessages(
            serverURL: serverURL,
            sessionID: "long-session",
            in: context,
            now: cachedAt.addingTimeInterval(60),
            newestLimit: 50
        )

        XCTAssertEqual(newestPage.count, 50)
        XCTAssertEqual(newestPage.map(\.messageId), (25..<75).map { "m\($0)" })
        XCTAssertEqual(try fetchCachedMessages(in: context).count, 75)
    }

    func testCachedMessagesNewestLimitReturnsExactlyOnePageOrFewer() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)

        for (sessionID, count) in [("exact-page", 50), ("short-page", 12)] {
            let messages = (0..<count).map { index in
                ChatMessage(
                    role: "assistant",
                    content: "\(sessionID) \(index)",
                    timestamp: 1_770_000_000 + Double(index),
                    messageId: "\(sessionID)-m\(index)"
                )
            }
            try await TestCacheStore.cacheMessages(
                messages,
                serverURL: serverURL,
                sessionID: sessionID,
                in: context,
                cachedAt: cachedAt
            )

            let cachedMessages = try CacheStore.cachedMessages(
                serverURL: serverURL,
                sessionID: sessionID,
                in: context,
                now: cachedAt.addingTimeInterval(60),
                newestLimit: 50
            )

            XCTAssertEqual(cachedMessages.map(\.messageId), messages.map(\.messageId))
        }
    }

    func testTranscriptCacheModelActorPreservesBoundedRichMessageValues() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date()
        let messages = (0..<75).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "Message \(index)",
                timestamp: Double(index),
                messageId: "m\(index)",
                toolCalls: [.object(["id": .string("tool-\(index)")])],
                contentParts: [.object(["type": .string("thinking"), "text": .string("Thought \(index)")])],
                reasoning: "Reasoning \(index)",
                attachments: [MessageAttachment(name: "file-\(index).txt", path: "/tmp/file-\(index).txt")]
            )
        }
        try await TestCacheStore.cacheMessages(
            messages,
            serverURL: serverURL,
            sessionID: "long-session",
            in: context,
            cachedAt: cachedAt
        )

        let reader = TranscriptCacheReader(modelContainer: context.container)
        let page = try await reader.cachedMessages(
            serverURL: serverURL,
            sessionID: "long-session",
            now: cachedAt.addingTimeInterval(60),
            newestLimit: 50
        )

        XCTAssertEqual(page.messages, Array(messages.suffix(50)))
        XCTAssertEqual(try fetchCachedMessages(in: context).count, 75)
    }

    func testTranscriptCacheReaderRemainsModelActorIsolated() async throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HermesMobile/Persistence/CacheStore.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertNotNil(
            source.range(
                of: #"@ModelActor\s+actor\s+TranscriptCacheReader\s*:\s*TranscriptCacheReading"#,
                options: .regularExpression
            ),
            "Bounded transcript fetch and mapping must remain isolated to a SwiftData model actor."
        )
        XCTAssertNil(
            source.range(
                of: #"@MainActor\s+(?:final\s+)?actor\s+TranscriptCacheReader"#,
                options: .regularExpression
            ),
            "TranscriptCacheReader must not regress onto MainActor."
        )
    }

    func testTranscriptCacheReaderHandlesExactShortEmptyAndExpiredPages() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date()
        for (sessionID, count) in [("exact", 50), ("short", 12), ("expired", 8)] {
            try await TestCacheStore.cacheMessages(
                (0..<count).map { index in
                    ChatMessage(
                        role: "assistant",
                        content: "\(sessionID) \(index)",
                        timestamp: Double(index),
                        messageId: "\(sessionID)-\(index)"
                    )
                },
                serverURL: serverURL,
                sessionID: sessionID,
                in: context,
                cachedAt: cachedAt
            )
        }
        let reader = TranscriptCacheReader(modelContainer: context.container)

        let exact = try await reader.cachedMessages(
            serverURL: serverURL,
            sessionID: "exact",
            now: cachedAt.addingTimeInterval(60),
            newestLimit: 50
        )
        let short = try await reader.cachedMessages(
            serverURL: serverURL,
            sessionID: "short",
            now: cachedAt.addingTimeInterval(60),
            newestLimit: 50
        )
        let empty = try await reader.cachedMessages(
            serverURL: serverURL,
            sessionID: "empty",
            now: cachedAt.addingTimeInterval(60),
            newestLimit: 50
        )
        let expired = try await reader.cachedMessages(
            serverURL: serverURL,
            sessionID: "expired",
            now: cachedAt.addingTimeInterval(CachePolicy.ttl + 1),
            newestLimit: 50
        )

        XCTAssertEqual(exact.messages.count, 50)
        XCTAssertEqual(short.messages.count, 12)
        XCTAssertTrue(empty.messages.isEmpty)
        XCTAssertTrue(expired.messages.isEmpty)
    }

    /// Repeatable local microbenchmark for the bounded SwiftData materialization +
    /// JSON decoding path. This is intentionally separate from signpost captures of
    /// real session opens: XCTest controls iterations, but the absolute result still
    /// depends on the host and must not be treated as a device performance target.
    func testNewestCachedMessagePageReadPerformance() async throws {
        if let storePath = ProcessInfo.processInfo.environment["HERMEX_TRANSCRIPT_DIAGNOSTIC_STORE"],
           let sessionID = ProcessInfo.processInfo.environment["HERMEX_TRANSCRIPT_DIAGNOSTIC_SESSION"],
           let serverURLString = ProcessInfo.processInfo.environment["HERMEX_TRANSCRIPT_DIAGNOSTIC_SERVER"],
           let serverURL = URL(string: serverURLString) {
            let configuration = ModelConfiguration(url: URL(fileURLWithPath: storePath))
            let container = try ModelContainer(
                for: CachedSession.self,
                CachedMessage.self,
                configurations: configuration
            )
            let reader = TranscriptCacheReader(modelContainer: container)
            let clock = ContinuousClock()
            var milliseconds: [Double] = []
            for _ in 0..<10 {
                let start = clock.now
                let page = try await reader.cachedMessages(
                    serverURL: serverURL,
                    sessionID: sessionID,
                    now: Date(),
                    newestLimit: 50
                )
                let duration = start.duration(to: clock.now)
                milliseconds.append(Double(duration.components.seconds) * 1_000
                    + Double(duration.components.attoseconds) / 1_000_000_000_000_000)
                XCTAssertLessThanOrEqual(page.messages.count, 50)
            }
            XCTContext.runActivity(
                named: "RealTranscriptCacheDiagnostic milliseconds=\(milliseconds)"
            ) { _ in }
            return
        }

        let context = try makeContext()
        let serverURL = URL(string: "https://performance.example.test")!
        let cachedAt = Date()
        let attachments = [
            MessageAttachment(
                name: "diagnostic.png",
                path: "/tmp/diagnostic.png",
                mime: "image/png",
                size: 4096,
                isImage: true
            )
        ]
        let contentParts: [JSONValue] = [
            .object(["type": .string("text"), "text": .string(String(repeating: "content ", count: 80))]),
            .object(["type": .string("thinking"), "thinking": .string(String(repeating: "reasoning ", count: 80))])
        ]
        let toolCalls: [JSONValue] = [
            .object([
                "id": .string("tool-1"),
                "name": .string("diagnostic_tool"),
                "arguments": .object(["path": .string("/tmp/diagnostic")])
            ])
        ]

        for index in 0..<1_000 {
            context.insert(CachedMessage(
                serverURLString: serverURL.absoluteString,
                sessionID: "long-session",
                message: ChatMessage(
                    role: index.isMultiple(of: 2) ? "user" : "assistant",
                    content: String(repeating: "Cached message \(index). ", count: 30),
                    timestamp: Double(index),
                    messageId: "message-\(index)",
                    toolCalls: toolCalls,
                    contentParts: contentParts,
                    reasoning: String(repeating: "Reasoning \(index). ", count: 20),
                    attachments: attachments
                ),
                sortIndex: index,
                cachedAt: cachedAt
            ))
        }
        try context.save()

        let reader = TranscriptCacheReader(modelContainer: context.container)
        let clock = ContinuousClock()
        var milliseconds: [Double] = []
        for _ in 0..<10 {
            let start = clock.now
            let page = try await reader.cachedMessages(
                serverURL: serverURL,
                sessionID: "long-session",
                now: cachedAt.addingTimeInterval(60),
                newestLimit: 50
            )
            let duration = start.duration(to: clock.now)
            milliseconds.append(Double(duration.components.seconds) * 1_000
                + Double(duration.components.attoseconds) / 1_000_000_000_000_000)
            XCTAssertEqual(page.messages.count, 50)
        }
        XCTContext.runActivity(named: "TranscriptCacheBenchmark milliseconds=\(milliseconds)") { _ in }
    }

    func testCachedMessagesIgnoresExpiredMessages() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let expiredNow = cachedAt.addingTimeInterval(CachePolicy.ttl + 1)

        try await TestCacheStore.cacheMessages(
            [
                ChatMessage(
                    role: "user",
                    content: "Expired",
                    timestamp: 1_770_000_001,
                    messageId: "expired"
                )
            ],
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            cachedAt: cachedAt
        )

        let cachedMessages = try CacheStore.cachedMessages(
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            now: expiredNow
        )

        XCTAssertTrue(cachedMessages.isEmpty)
    }

    func testCacheMaintenanceDeletesExpiredSessionsAndMessagesOnWrite() async throws {
        let context = try makeContext()
        let oldServerURL = URL(string: "https://old.example.test")!
        let triggerServerURL = URL(string: "https://trigger.example.test")!
        let oldCachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let currentCachedAt = oldCachedAt.addingTimeInterval(CachePolicy.ttl + 1)

        let oldSessions = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "expired-session", "title": "Expired", "last_message_at": 1770000000, "archived": false}
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(oldSessions.sessions),
            serverURL: oldServerURL,
            in: context,
            cachedAt: oldCachedAt
        )

        try await TestCacheStore.cacheMessages(
            [
                ChatMessage(
                    role: "user",
                    content: "Expired message",
                    timestamp: 1_770_000_000,
                    messageId: "expired-message"
                )
            ],
            serverURL: oldServerURL,
            sessionID: "expired-session",
            in: context,
            cachedAt: oldCachedAt
        )

        let triggerSessions = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "fresh-session", "title": "Fresh", "last_message_at": 1770604801, "archived": false}
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(triggerSessions.sessions),
            serverURL: triggerServerURL,
            in: context,
            cachedAt: currentCachedAt
        )

        XCTAssertEqual(try fetchCachedSessions(in: context).map(\.sessionID), ["fresh-session"])
        XCTAssertTrue(try fetchCachedMessages(in: context).isEmpty)
    }

    func testMaintenanceDoesNotDeleteRowsRefreshedFromExpiredTimestamp() async throws {
        let context = try makeContext()
        let server = try XCTUnwrap(URL(string: "https://refresh-expired.example.test"))
        let oldDate = Date(timeIntervalSince1970: 1_770_000_000)
        let refreshedDate = oldDate.addingTimeInterval(CachePolicy.ttl + 1)
        let message = ChatMessage(
            role: "user",
            content: "Still current",
            timestamp: 1_770_000_000,
            messageId: "refresh-me"
        )

        try await TestCacheStore.cacheMessages(
            [message],
            serverURL: server,
            sessionID: "s",
            in: context,
            cachedAt: oldDate
        )
        try await TestCacheStore.cacheMessages(
            [message],
            serverURL: server,
            sessionID: "s",
            in: context,
            cachedAt: refreshedDate
        )

        let cached = try fetchCachedMessages(in: context)
        XCTAssertEqual(cached.map(\.messageId), ["refresh-me"])
        XCTAssertEqual(cached.first?.cachedAt, refreshedDate)
        XCTAssertEqual(cached.first?.expiresAt, refreshedDate.addingTimeInterval(CachePolicy.ttl))
    }

    func testCacheMaintenanceEvictsOldestMessagesAboveLimit() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)

        for index in 0...CachePolicy.maxMessages {
            context.insert(
                CachedMessage(
                    serverURLString: serverURL.absoluteString,
                    sessionID: "abc123",
                    message: ChatMessage(
                        role: "user",
                        content: "Message \(index)",
                        timestamp: Double(index),
                        messageId: "message-\(index)"
                    ),
                    sortIndex: index,
                    cachedAt: cachedAt
                )
            )
        }
        try context.save()

        let triggerSessions = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "abc123", "title": "Trigger", "last_message_at": 1770000000, "archived": false}
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(triggerSessions.sessions),
            serverURL: serverURL,
            in: context,
            cachedAt: cachedAt
        )

        let cachedMessages = try fetchCachedMessages(in: context)

        XCTAssertEqual(cachedMessages.count, CachePolicy.maxMessages)
        XCTAssertNil(cachedMessages.first { $0.messageId == "message-0" })
        XCTAssertNotNil(cachedMessages.first { $0.messageId == "message-1" })
        XCTAssertNotNil(cachedMessages.first { $0.messageId == "message-\(CachePolicy.maxMessages)" })
    }

    func testClearAllDeletesCachedSessionsAndMessages() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let response = try decodeSessions("""
        {
          "sessions": [
            {"session_id": "abc123", "title": "Cached", "last_message_at": 1770000000, "archived": false}
          ]
        }
        """)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(response.sessions),
            serverURL: serverURL,
            in: context,
            cachedAt: cachedAt
        )

        try await TestCacheStore.cacheMessages(
            [
                ChatMessage(
                    role: "user",
                    content: "Cached message",
                    timestamp: 1_770_000_000,
                    messageId: "m1"
                )
            ],
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            cachedAt: cachedAt
        )

        try await TestCacheStore.clearAll(in: context)

        XCTAssertTrue(try fetchCachedSessions(in: context).isEmpty)
        XCTAssertTrue(try fetchCachedMessages(in: context).isEmpty)
    }

    func testCacheMessagesRoundTripsAttachments() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let now = cachedAt.addingTimeInterval(60)

        let messages = [
            ChatMessage(
                role: "user",
                content: "Here is a photo",
                timestamp: 1_770_000_000,
                messageId: "m1",
                attachments: [
                    MessageAttachment(
                        name: "photo.png",
                        path: "/uploads/photo.png",
                        mime: "image/png",
                        size: 12345,
                        isImage: true
                    )
                ]
            )
        ]

        try await TestCacheStore.cacheMessages(
            messages,
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            cachedAt: cachedAt
        )

        let cachedMessages = try CacheStore.cachedMessages(
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            now: now
        )

        XCTAssertEqual(cachedMessages.count, 1)
        let attachment = try XCTUnwrap(cachedMessages.first?.attachments?.first)
        XCTAssertEqual(attachment.name, "photo.png")
        XCTAssertEqual(attachment.path, "/uploads/photo.png")
        XCTAssertEqual(attachment.mime, "image/png")
        XCTAssertEqual(attachment.size, 12345)
        XCTAssertEqual(attachment.isImage, true)
    }

    func testCacheMessagesRoundTripsToolCallAndStructuredContentFields() async throws {
        let context = try makeContext()
        let serverURL = URL(string: "https://example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let now = cachedAt.addingTimeInterval(60)

        let toolCalls: [JSONValue] = [
            .object([
                "id": .string("call-1"),
                "function": .object([
                    "name": .string("read_file"),
                    "arguments": .string("{\"path\": \"notes.txt\"}")
                ])
            ])
        ]
        let contentParts: [JSONValue] = [
            .object(["type": .string("text"), "text": .string("Reading the file")]),
            .object(["type": .string("tool_use"), "id": .string("call-1")])
        ]

        let messages = [
            ChatMessage(
                role: "assistant",
                content: "Reading the file",
                timestamp: 1_770_000_000,
                messageId: "m1",
                toolUseId: "call-1",
                toolCalls: toolCalls,
                contentParts: contentParts
            )
        ]

        try await TestCacheStore.cacheMessages(
            messages,
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            cachedAt: cachedAt
        )

        let cachedMessages = try CacheStore.cachedMessages(
            serverURL: serverURL,
            sessionID: "abc123",
            in: context,
            now: now
        )

        XCTAssertEqual(cachedMessages.count, 1)
        let restored = try XCTUnwrap(cachedMessages.first)
        XCTAssertEqual(restored.toolUseId, "call-1")
        XCTAssertEqual(restored.toolCalls, toolCalls)
        XCTAssertEqual(restored.contentParts, contentParts)
    }

    // MARK: - Per-server isolation (#18)

    func testCachedMessagesAreScopedToTheirServerForTheSameSessionID() async throws {
        let context = try makeContext()
        let serverA = URL(string: "https://a.example.test")!
        let serverB = URL(string: "https://b.example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let now = cachedAt.addingTimeInterval(60)

        try await TestCacheStore.cacheMessages(
            [ChatMessage(role: "user", content: "From A", timestamp: 1_770_000_000, messageId: "m1")],
            serverURL: serverA,
            sessionID: "shared",
            in: context,
            cachedAt: cachedAt
        )
        try await TestCacheStore.cacheMessages(
            [ChatMessage(role: "user", content: "From B", timestamp: 1_770_000_000, messageId: "m1")],
            serverURL: serverB,
            sessionID: "shared",
            in: context,
            cachedAt: cachedAt
        )

        let aMessages = try CacheStore.cachedMessages(serverURL: serverA, sessionID: "shared", in: context, now: now)
        let bMessages = try CacheStore.cachedMessages(serverURL: serverB, sessionID: "shared", in: context, now: now)

        XCTAssertEqual(aMessages.map(\.content), ["From A"])
        XCTAssertEqual(bMessages.map(\.content), ["From B"])
    }

    func testCacheSessionsForOneServerDoesNotDeleteAnotherServersStaleSessions() async throws {
        let context = try makeContext()
        let serverA = URL(string: "https://a.example.test")!
        let serverB = URL(string: "https://b.example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let now = cachedAt.addingTimeInterval(60)

        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(decodeSessions("""
            {"sessions": [{"session_id": "a1", "title": "A one", "last_message_at": 1770000000, "archived": false}]}
            """).sessions),
            serverURL: serverA,
            in: context,
            cachedAt: cachedAt
        )
        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(decodeSessions("""
            {"sessions": [{"session_id": "b1", "title": "B one", "last_message_at": 1770000000, "archived": false}]}
            """).sessions),
            serverURL: serverB,
            in: context,
            cachedAt: cachedAt
        )

        // Re-cache server A with a different set so its stale-removal pass runs.
        // It must drop A's "a1" without touching server B's "b1".
        try await TestCacheStore.cacheSessions(
            try XCTUnwrap(decodeSessions("""
            {"sessions": [{"session_id": "a2", "title": "A two", "last_message_at": 1770000100, "archived": false}]}
            """).sessions),
            serverURL: serverA,
            in: context,
            cachedAt: cachedAt
        )

        let aSessions = try CacheStore.cachedSessions(serverURL: serverA, in: context, now: now)
        let bSessions = try CacheStore.cachedSessions(serverURL: serverB, in: context, now: now)

        XCTAssertEqual(aSessions.map(\.sessionId), ["a2"])
        XCTAssertEqual(bSessions.map(\.sessionId), ["b1"])
    }

    func testCacheMessagesForOneServerDoesNotDeleteAnotherServersMessages() async throws {
        let context = try makeContext()
        let serverA = URL(string: "https://a.example.test")!
        let serverB = URL(string: "https://b.example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let now = cachedAt.addingTimeInterval(60)

        try await TestCacheStore.cacheMessages(
            [ChatMessage(role: "user", content: "From A", timestamp: 1_770_000_000, messageId: "m1")],
            serverURL: serverA,
            sessionID: "shared",
            in: context,
            cachedAt: cachedAt
        )
        try await TestCacheStore.cacheMessages(
            [ChatMessage(role: "user", content: "From B", timestamp: 1_770_000_000, messageId: "m1")],
            serverURL: serverB,
            sessionID: "shared",
            in: context,
            cachedAt: cachedAt
        )

        // Re-cache server A's session with no messages so its stale-removal pass
        // wipes A's window; server B's identically-keyed session must survive.
        try await TestCacheStore.cacheMessages(
            [],
            serverURL: serverA,
            sessionID: "shared",
            in: context,
            cachedAt: cachedAt
        )

        let aMessages = try CacheStore.cachedMessages(serverURL: serverA, sessionID: "shared", in: context, now: now)
        let bMessages = try CacheStore.cachedMessages(serverURL: serverB, sessionID: "shared", in: context, now: now)

        XCTAssertTrue(aMessages.isEmpty)
        XCTAssertEqual(bMessages.map(\.content), ["From B"])
    }

    func testClearCacheRemovesOnlyTheGivenServersData() async throws {
        let context = try makeContext()
        let serverA = URL(string: "https://a.example.test")!
        let serverB = URL(string: "https://b.example.test")!
        let cachedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let now = cachedAt.addingTimeInterval(60)

        for (server, title) in [(serverA, "A one"), (serverB, "B one")] {
            try await TestCacheStore.cacheSessions(
                try XCTUnwrap(decodeSessions("""
                {"sessions": [{"session_id": "s1", "title": "\(title)", "last_message_at": 1770000000, "archived": false}]}
                """).sessions),
                serverURL: server,
                in: context,
                cachedAt: cachedAt
            )
            try await TestCacheStore.cacheMessages(
                [ChatMessage(role: "user", content: title, timestamp: 1_770_000_000, messageId: "m1")],
                serverURL: server,
                sessionID: "s1",
                in: context,
                cachedAt: cachedAt
            )
        }

        try await TestCacheStore.clearCache(for: serverA, in: context)

        XCTAssertTrue(try CacheStore.cachedSessions(serverURL: serverA, in: context, now: now).isEmpty)
        XCTAssertTrue(try CacheStore.cachedMessages(serverURL: serverA, sessionID: "s1", in: context, now: now).isEmpty)
        XCTAssertEqual(
            try CacheStore.cachedSessions(serverURL: serverB, in: context, now: now).map(\.sessionId),
            ["s1"]
        )
        XCTAssertEqual(
            try CacheStore.cachedMessages(serverURL: serverB, sessionID: "s1", in: context, now: now).map(\.content),
            ["B one"]
        )
    }

    func testActorWriterUsesBoundedFetchesForFiveHundredMessagesOffMainThread() async throws {
        let context = try makeContext()
        let writer = CacheWriter(modelContainer: context.container)
        let server = try XCTUnwrap(URL(string: "https://bounded.example.test"))
        let sessionID = "bounded"
        let generation = UUID()
        await writer.activate(
            scope: .messages(serverURLString: server.absoluteString, sessionID: sessionID),
            generation: generation
        )

        let messages = (0..<500).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "Bounded message \(index)",
                timestamp: Double(index),
                messageId: "bounded-\(index)"
            )
        }
        let diagnostic = try await writer.write(.replaceMessages(CacheMessageListSnapshot(
            serverURL: server,
            sessionID: sessionID,
            messages: messages,
            generation: generation
        )))

        XCTAssertLessThanOrEqual(diagnostic.fetchCount, 5)
        XCTAssertEqual(diagnostic.objectsInserted, 500)
        XCTAssertFalse(diagnostic.ranOnMainActor)
        XCTAssertGreaterThan(diagnostic.totalNanoseconds, 0)
        XCTAssertEqual(try fetchCachedMessages(in: context).count, 500)
    }

    func testAutomaticMaintenanceCoalescesTinyWriteBurstAndRunsAtThreshold() async throws {
        let context = try makeContext()
        let writer = CacheWriter(modelContainer: context.container)
        let server = try XCTUnwrap(URL(string: "https://maintenance.example.test"))
        let generation = UUID()
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        await writer.activate(
            scope: .sessions(serverURLString: server.absoluteString),
            generation: generation
        )

        let initial = try await writer.write(.replaceSessions(CacheSessionListSnapshot(
            serverURL: server,
            sessions: [SessionSummary(sessionId: "s", title: "Initial")],
            cachedAt: now,
            generation: generation
        )))
        XCTAssertGreaterThan(initial.fetchCount, 1)

        var diagnostic = CacheWriteDiagnosticSnapshot()
        for index in 1..<CachePersistenceWriter.maintenanceWriteThreshold {
            diagnostic = try await writer.write(.upsertSession(CacheSessionSnapshot(
                serverURL: server,
                session: SessionSummary(sessionId: "s", title: "Update \(index)"),
                cachedAt: now.addingTimeInterval(Double(index)),
                generation: generation
            )))
            XCTAssertEqual(diagnostic.fetchCount, 1)
        }

        diagnostic = try await writer.write(.upsertSession(CacheSessionSnapshot(
            serverURL: server,
            session: SessionSummary(sessionId: "s", title: "Threshold"),
            cachedAt: now.addingTimeInterval(20),
            generation: generation
        )))
        XCTAssertGreaterThan(diagnostic.fetchCount, 1)
    }

    func testPendingMessageSnapshotsCoalesceToNewestValue() async throws {
        let persistence = ControlledCachePersistenceWriter(suspendsFirstRequest: true)
        let writer = CacheWriter(persistence: persistence)
        let server = try XCTUnwrap(URL(string: "https://coalesce.example.test"))
        let generation = UUID()
        let scope = CacheWriteScope.messages(serverURLString: server.absoluteString, sessionID: "same")
        await writer.activate(scope: scope, generation: generation)

        let blocker = Task { try await writer.write(.maintenance(now: Date())) }
        await persistence.waitUntilFirstRequestStarts()

        let older = Task {
            try await writer.write(.replaceMessages(CacheMessageListSnapshot(
                serverURL: server,
                sessionID: "same",
                messages: [ChatMessage(role: "user", content: "older", timestamp: 1, messageId: "m")],
                generation: generation
            )))
        }
        await waitForPendingWriteCount(1, in: writer)

        let newest = Task {
            try await writer.write(.replaceMessages(CacheMessageListSnapshot(
                serverURL: server,
                sessionID: "same",
                messages: [ChatMessage(role: "user", content: "newest", timestamp: 2, messageId: "m")],
                generation: generation
            )))
        }
        await waitForPendingWriteCount(1, in: writer)
        await persistence.resumeFirstRequest()

        _ = try await blocker.value
        let olderDiagnostic = try await older.value
        let newestDiagnostic = try await newest.value
        let finalContents = await persistence.messageContents(for: scope)
        let executedRequestCount = await persistence.executedRequestCount()
        XCTAssertEqual(olderDiagnostic.coalescedSnapshots, 1)
        XCTAssertEqual(newestDiagnostic.coalescedSnapshots, 1)
        XCTAssertEqual(finalContents, ["newest"])
        XCTAssertEqual(executedRequestCount, 2)
    }

    func testClearServerIsBarrierForOlderQueuedWrite() async throws {
        let persistence = ControlledCachePersistenceWriter(suspendsFirstRequest: true)
        let writer = CacheWriter(persistence: persistence)
        let server = try XCTUnwrap(URL(string: "https://barrier.example.test"))
        let generation = UUID()
        let scope = CacheWriteScope.messages(serverURLString: server.absoluteString, sessionID: "s")
        await writer.activate(scope: scope, generation: generation)

        let blocker = Task { try await writer.write(.maintenance(now: Date())) }
        await persistence.waitUntilFirstRequestStarts()
        let oldWrite = Task {
            try await writer.write(.replaceMessages(CacheMessageListSnapshot(
                serverURL: server,
                sessionID: "s",
                messages: [ChatMessage(role: "user", content: "old", timestamp: 1, messageId: "old")],
                generation: generation
            )))
        }
        await waitForPendingWriteCount(1, in: writer)
        let clear = Task {
            try await writer.write(.clearServer(serverURLString: server.absoluteString))
        }
        await waitForPendingWriteCount(2, in: writer)
        await persistence.resumeFirstRequest()

        _ = try await blocker.value
        let oldDiagnostic = try await oldWrite.value
        _ = try await clear.value
        let finalContents = await persistence.messageContents(for: scope)
        let executedRequestCount = await persistence.executedRequestCount()
        XCTAssertTrue(oldDiagnostic.skippedStaleGeneration)
        XCTAssertEqual(finalContents, [])
        XCTAssertEqual(executedRequestCount, 2)
    }

    func testNewGenerationDropsOlderQueuedSnapshotAcrossRapidSwitching() async throws {
        let persistence = ControlledCachePersistenceWriter(suspendsFirstRequest: true)
        let writer = CacheWriter(persistence: persistence)
        let server = try XCTUnwrap(URL(string: "https://switch.example.test"))
        let scopeA = CacheWriteScope.messages(serverURLString: server.absoluteString, sessionID: "A")
        let scopeB = CacheWriteScope.messages(serverURLString: server.absoluteString, sessionID: "B")
        let generationA1 = UUID()
        let generationA2 = UUID()
        let generationB = UUID()
        await writer.activate(scope: scopeA, generation: generationA1)
        await writer.activate(scope: scopeB, generation: generationB)

        let blocker = Task { try await writer.write(.maintenance(now: Date())) }
        await persistence.waitUntilFirstRequestStarts()
        let staleA = Task {
            try await writer.write(.replaceMessages(CacheMessageListSnapshot(
                serverURL: server,
                sessionID: "A",
                messages: [ChatMessage(role: "user", content: "stale A", timestamp: 1, messageId: "a")],
                generation: generationA1
            )))
        }
        await waitForPendingWriteCount(1, in: writer)

        await writer.activate(scope: scopeA, generation: generationA2)
        let bWrite = Task {
            try await writer.write(.replaceMessages(CacheMessageListSnapshot(
                serverURL: server,
                sessionID: "B",
                messages: [ChatMessage(role: "user", content: "B", timestamp: 2, messageId: "b")],
                generation: generationB
            )))
        }
        let newestA = Task {
            try await writer.write(.replaceMessages(CacheMessageListSnapshot(
                serverURL: server,
                sessionID: "A",
                messages: [ChatMessage(role: "user", content: "newest A", timestamp: 3, messageId: "a")],
                generation: generationA2
            )))
        }
        await persistence.resumeFirstRequest()

        _ = try await blocker.value
        let staleDiagnostic = try await staleA.value
        _ = try await bWrite.value
        _ = try await newestA.value
        let finalA = await persistence.messageContents(for: scopeA)
        let finalB = await persistence.messageContents(for: scopeB)
        XCTAssertTrue(staleDiagnostic.skippedStaleGeneration)
        XCTAssertEqual(finalA, ["newest A"])
        XCTAssertEqual(finalB, ["B"])
    }

    func testCancellingQueuedWritePreventsPersistence() async throws {
        let persistence = ControlledCachePersistenceWriter(suspendsFirstRequest: true)
        let writer = CacheWriter(persistence: persistence)
        let server = try XCTUnwrap(URL(string: "https://cancel.example.test"))
        let generation = UUID()
        let scope = CacheWriteScope.messages(serverURLString: server.absoluteString, sessionID: "s")
        await writer.activate(scope: scope, generation: generation)

        let blocker = Task { try await writer.write(.maintenance(now: Date())) }
        await persistence.waitUntilFirstRequestStarts()
        let cancelled = Task {
            try await writer.write(.replaceMessages(CacheMessageListSnapshot(
                serverURL: server,
                sessionID: "s",
                messages: [ChatMessage(role: "user", content: "cancelled", timestamp: 1, messageId: "m")],
                generation: generation
            )))
        }
        await waitForPendingWriteCount(1, in: writer)
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("The queued cache write should be cancelled.")
        } catch is CancellationError {
            // Expected.
        }
        await persistence.resumeFirstRequest()
        _ = try await blocker.value
        let finalContents = await persistence.messageContents(for: scope)
        XCTAssertEqual(finalContents, [])
    }

    func testWriterErrorPropagatesWithoutBecomingSuccessfulPersistence() async throws {
        let writer = CacheWriter(persistence: FailingCachePersistenceWriter())
        do {
            _ = try await writer.write(.maintenance(now: Date()))
            XCTFail("Expected the injected persistence error.")
        } catch let error as ControlledCachePersistenceError {
            XCTAssertEqual(error, .injected)
        }
    }

    private func waitForPendingWriteCount(_ expected: Int, in writer: CacheWriter) async {
#if DEBUG
        for _ in 0..<1_000 {
            if await writer.pendingWriteCountForTesting() == expected { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expected) queued cache writes.")
#endif
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CachedSession.self,
            CachedMessage.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    private func decodeSessions(_ json: String) throws -> SessionsResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SessionsResponse.self, from: Data(json.utf8))
    }

    private func fetchCachedSessions(in context: ModelContext) throws -> [CachedSession] {
        try context.fetch(FetchDescriptor<CachedSession>())
    }

    private func fetchCachedMessages(in context: ModelContext) throws -> [CachedMessage] {
        try context.fetch(FetchDescriptor<CachedMessage>())
    }
}

private enum ControlledCachePersistenceError: Error, Equatable {
    case injected
}

private struct FailingCachePersistenceWriter: CachePersistenceWriting {
    func execute(_ request: CacheWriteRequest) async throws -> CacheWriteDiagnosticSnapshot {
        throw ControlledCachePersistenceError.injected
    }
}

private actor ControlledCachePersistenceWriter: CachePersistenceWriting {
    private let suspendsFirstRequest: Bool
    private var didStartFirstRequest = false
    private var firstStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstResumeContinuation: CheckedContinuation<Void, Never>?
    private var executedRequests: [CacheWriteRequest] = []
    private var messagesByScope: [CacheWriteScope: [String]] = [:]

    init(suspendsFirstRequest: Bool) {
        self.suspendsFirstRequest = suspendsFirstRequest
    }

    func execute(_ request: CacheWriteRequest) async throws -> CacheWriteDiagnosticSnapshot {
        executedRequests.append(request)
        if suspendsFirstRequest, !didStartFirstRequest {
            didStartFirstRequest = true
            for waiter in firstStartWaiters { waiter.resume() }
            firstStartWaiters = []
            await withCheckedContinuation { continuation in
                firstResumeContinuation = continuation
            }
        }

        switch request {
        case .replaceMessages(let snapshot):
            let scope = CacheWriteScope.messages(
                serverURLString: snapshot.serverURLString,
                sessionID: snapshot.sessionID
            )
            messagesByScope[scope] = snapshot.messages.compactMap(\.content)
        case .clearServer(let serverURLString):
            messagesByScope = messagesByScope.filter { $0.key.serverURLString != serverURLString }
        case .clearAll:
            messagesByScope = [:]
        case .replaceSessions, .upsertSession, .maintenance:
            break
        }
        return CacheWriteDiagnosticSnapshot()
    }

    func waitUntilFirstRequestStarts() async {
        guard !didStartFirstRequest else { return }
        await withCheckedContinuation { continuation in
            firstStartWaiters.append(continuation)
        }
    }

    func resumeFirstRequest() {
        firstResumeContinuation?.resume()
        firstResumeContinuation = nil
    }

    func messageContents(for scope: CacheWriteScope) -> [String] {
        messagesByScope[scope] ?? []
    }

    func executedRequestCount() -> Int {
        executedRequests.count
    }
}
