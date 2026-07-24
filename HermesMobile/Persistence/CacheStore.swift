import Foundation
import os
import SwiftData

enum TranscriptPerformanceSignpost {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.anthonyarmijo.hermex",
        category: .pointsOfInterest
    )

    /// Starts a privacy-safe Points of Interest interval. Callers may continue to
    /// pass a session identifier so the instrumentation API stays convenient, but
    /// identifiers are deliberately never emitted to the unified log.
    static func begin(_ name: StaticString, sessionID _: String = "") -> OSSignpostID {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        return signpostID
    }

    static func end(
        _ name: StaticString,
        signpostID: OSSignpostID,
        sessionID _: String = "",
        count: Int? = nil
    ) {
        if let count {
            os_signpost(.end, log: log, name: name, signpostID: signpostID, "count=%{public}ld", count)
        } else {
            os_signpost(.end, log: log, name: name, signpostID: signpostID)
        }
    }

    static func event(_ name: StaticString, sessionID _: String = "", count: Int? = nil) {
        if let count {
            os_signpost(.event, log: log, name: name, "count=%{public}ld", count)
        } else {
            os_signpost(.event, log: log, name: name)
        }
    }

    static func interval<Value>(
        _ name: StaticString,
        sessionID: String = "",
        count: Int? = nil,
        operation: () throws -> Value
    ) rethrows -> Value {
        let signpostID = begin(name, sessionID: sessionID)
        defer { end(name, signpostID: signpostID, sessionID: sessionID, count: count) }
        return try operation()
    }
}

struct TranscriptCachePage: Sendable {
    let messages: [ChatMessage]
}

struct CacheWriteDiagnosticSnapshot: Equatable, Sendable {
    var fetchCount = 0
    var objectsFetched = 0
    var objectsUpdated = 0
    var objectsInserted = 0
    var objectsDeleted = 0
    var maintenanceDeleted = 0
    var ranOnMainActor = false
}

private struct CacheMaintenanceDiagnostic {
    let fetchCount: Int
    let objectsFetched: Int
    let objectsDeleted: Int
}

protocol TranscriptCacheReading: Sendable {
    func cachedMessages(
        serverURL: URL,
        sessionID: String,
        now: Date,
        newestLimit: Int
    ) async throws -> TranscriptCachePage
}

/// Read-only SwiftData boundary for opening a transcript. Its generated model
/// context stays isolated to this actor; only checked-Sendable value models leave it.
@ModelActor
actor TranscriptCacheReader: TranscriptCacheReading {
    func cachedMessages(
        serverURL: URL,
        sessionID: String,
        now: Date = Date(),
        newestLimit: Int
    ) throws -> TranscriptCachePage {
        try Task.checkCancellation()
        guard newestLimit > 0 else {
            return TranscriptCachePage(messages: [])
        }

        let serverURLString = serverURL.absoluteString
        let predicate = #Predicate<CachedMessage> { cachedMessage in
            cachedMessage.serverURLString == serverURLString
                && cachedMessage.sessionID == sessionID
                && cachedMessage.expiresAt > now
        }
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
        )
        descriptor.fetchLimit = newestLimit

        let cachedMessages = try TranscriptPerformanceSignpost.interval(
            "Transcript cache fetch",
            sessionID: sessionID
        ) {
            try modelContext.fetch(descriptor)
        }

        try Task.checkCancellation()
        let messages = TranscriptPerformanceSignpost.interval(
            "Cached message mapping",
            sessionID: sessionID
        ) {
            cachedMessages
                .reversed()
                .map(ChatMessage.init(cachedMessage:))
        }
        try Task.checkCancellation()
        TranscriptPerformanceSignpost.event(
            "Cached messages ready off-main",
            sessionID: sessionID
        )

        return TranscriptCachePage(messages: messages)
    }
}

enum CacheStore {
    @MainActor
    static func cachedSessions(
        serverURL: URL,
        in context: ModelContext,
        now: Date = Date()
    ) throws -> [SessionSummary] {
        let serverURLString = serverURL.absoluteString
        let descriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { cachedSession in
                cachedSession.serverURLString == serverURLString
            }
        )

        return try context.fetch(descriptor)
            .filter { $0.archived != true && $0.expiresAt > now }
            .map(SessionSummary.init(cachedSession:))
    }

    @MainActor
    static func cachedMessages(
        serverURL: URL,
        sessionID: String,
        in context: ModelContext,
        now: Date = Date(),
        newestLimit: Int? = nil
    ) throws -> [ChatMessage] {
        let serverURLString = serverURL.absoluteString
        let predicate = #Predicate<CachedMessage> { cachedMessage in
            cachedMessage.serverURLString == serverURLString
                && cachedMessage.sessionID == sessionID
                && cachedMessage.expiresAt > now
        }

        if let newestLimit {
            guard newestLimit > 0 else { return [] }

            var descriptor = FetchDescriptor<CachedMessage>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
            )
            descriptor.fetchLimit = newestLimit

            let cachedMessages = try TranscriptPerformanceSignpost.interval(
                "Transcript cache fetch",
                sessionID: sessionID
            ) {
                try context.fetch(descriptor)
            }

            return TranscriptPerformanceSignpost.interval(
                "Cached message mapping",
                sessionID: sessionID
            ) {
                cachedMessages
                    .reversed()
                    .map(ChatMessage.init(cachedMessage:))
            }
        }

        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortIndex)]
        )

        let cachedMessages = try TranscriptPerformanceSignpost.interval(
            "Transcript cache fetch",
            sessionID: sessionID
        ) {
            try context.fetch(descriptor)
        }

        return TranscriptPerformanceSignpost.interval(
            "Cached message mapping",
            sessionID: sessionID
        ) {
            cachedMessages.map(ChatMessage.init(cachedMessage:))
        }
    }

    @MainActor
    static func cacheSessions(
        _ sessions: [SessionSummary],
        serverURL: URL,
        in context: ModelContext,
        cachedAt: Date = Date()
    ) throws {
        let reconciliationSignpost = TranscriptPerformanceSignpost.begin("Cache write total")
        defer {
            TranscriptPerformanceSignpost.end(
                "Cache write total",
                signpostID: reconciliationSignpost,
                count: sessions.count
            )
        }
        let writeStageSignpost = TranscriptPerformanceSignpost.begin("Cache write reconciliation")
        let serverURLString = serverURL.absoluteString
        let cacheableSessions = sessions.filter { $0.archived != true && $0.sessionId != nil }
        let freshKeys = Set(cacheableSessions.compactMap { session -> String? in
            guard let sessionID = session.sessionId else { return nil }
            return CachedSession.cacheKey(serverURLString: serverURLString, sessionID: sessionID)
        })

        for session in cacheableSessions {
            guard let sessionID = session.sessionId else { continue }
            let cacheKey = CachedSession.cacheKey(serverURLString: serverURLString, sessionID: sessionID)
            if let cachedSession = try cachedSession(cacheKey: cacheKey, in: context) {
                cachedSession.apply(session, cachedAt: cachedAt)
            } else {
                context.insert(CachedSession(serverURLString: serverURLString, session: session, cachedAt: cachedAt))
            }
        }

        let descriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { cachedSession in
                cachedSession.serverURLString == serverURLString
            }
        )
        let staleSessions = try context.fetch(descriptor).filter { !freshKeys.contains($0.cacheKey) }
        for staleSession in staleSessions {
            context.delete(staleSession)
        }
        TranscriptPerformanceSignpost.end(
            "Cache write reconciliation",
            signpostID: writeStageSignpost,
            count: cacheableSessions.count
        )

        _ = try TranscriptPerformanceSignpost.interval("Cache maintenance") {
            try performMaintenance(in: context, now: cachedAt)
        }
        try TranscriptPerformanceSignpost.interval("Cache save") {
            try context.save()
        }
    }

    @MainActor
    static func cacheSession(
        _ session: SessionSummary,
        serverURL: URL,
        in context: ModelContext,
        cachedAt: Date = Date()
    ) throws {
        guard let sessionID = session.sessionId else { return }
        let reconciliationSignpost = TranscriptPerformanceSignpost.begin("Cache write total")
        defer {
            TranscriptPerformanceSignpost.end(
                "Cache write total",
                signpostID: reconciliationSignpost,
                count: 1
            )
        }
        let writeStageSignpost = TranscriptPerformanceSignpost.begin("Cache write reconciliation")

        let serverURLString = serverURL.absoluteString
        let cacheKey = CachedSession.cacheKey(serverURLString: serverURLString, sessionID: sessionID)

        if session.archived == true {
            if let cachedSession = try cachedSession(cacheKey: cacheKey, in: context) {
                context.delete(cachedSession)
            }
        } else if let cachedSession = try cachedSession(cacheKey: cacheKey, in: context) {
            cachedSession.apply(session, cachedAt: cachedAt)
        } else {
            context.insert(CachedSession(serverURLString: serverURLString, session: session, cachedAt: cachedAt))
        }
        TranscriptPerformanceSignpost.end(
            "Cache write reconciliation",
            signpostID: writeStageSignpost,
            count: 1
        )

        _ = try TranscriptPerformanceSignpost.interval("Cache maintenance") {
            try performMaintenance(in: context, now: cachedAt)
        }
        try TranscriptPerformanceSignpost.interval("Cache save") {
            try context.save()
        }
    }

    @MainActor
    static func cacheMessages(
        _ messages: [ChatMessage],
        serverURL: URL,
        sessionID: String,
        in context: ModelContext,
        cachedAt: Date = Date(),
        diagnostics: ((CacheWriteDiagnosticSnapshot) -> Void)? = nil
    ) throws {
        var diagnostic = CacheWriteDiagnosticSnapshot(ranOnMainActor: Thread.isMainThread)
        defer { diagnostics?(diagnostic) }
        let reconciliationSignpost = TranscriptPerformanceSignpost.begin("Cache write total")
        defer {
            TranscriptPerformanceSignpost.end(
                "Cache write total",
                signpostID: reconciliationSignpost,
                count: messages.count
            )
        }
        let writeStageSignpost = TranscriptPerformanceSignpost.begin("Cache write reconciliation")
        let serverURLString = serverURL.absoluteString
        let freshKeys = Set(messages.enumerated().map { offset, message in
            CachedMessage.cacheKey(
                serverURLString: serverURLString,
                sessionID: sessionID,
                message: message,
                sortIndex: offset
            )
        })

        for (offset, message) in messages.enumerated() {
            let cacheKey = CachedMessage.cacheKey(
                serverURLString: serverURLString,
                sessionID: sessionID,
                message: message,
                sortIndex: offset
            )
            diagnostic.fetchCount += 1
            if let cachedMessage = try cachedMessage(cacheKey: cacheKey, in: context) {
                diagnostic.objectsFetched += 1
                diagnostic.objectsUpdated += 1
                cachedMessage.apply(message, sortIndex: offset, cachedAt: cachedAt)
            } else {
                diagnostic.objectsInserted += 1
                context.insert(CachedMessage(
                    serverURLString: serverURLString,
                    sessionID: sessionID,
                    message: message,
                    sortIndex: offset,
                    cachedAt: cachedAt
                ))
            }
        }

        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { cachedMessage in
                cachedMessage.serverURLString == serverURLString
                    && cachedMessage.sessionID == sessionID
            }
        )
        diagnostic.fetchCount += 1
        let fetchedMessages = try context.fetch(descriptor)
        diagnostic.objectsFetched += fetchedMessages.count
        let staleMessages = fetchedMessages.filter { !freshKeys.contains($0.cacheKey) }
        for staleMessage in staleMessages {
            diagnostic.objectsDeleted += 1
            context.delete(staleMessage)
        }
        TranscriptPerformanceSignpost.end(
            "Cache write reconciliation",
            signpostID: writeStageSignpost,
            count: messages.count
        )

        let maintenance = try TranscriptPerformanceSignpost.interval("Cache maintenance") {
            try performMaintenance(in: context, now: cachedAt)
        }
        diagnostic.fetchCount += maintenance.fetchCount
        diagnostic.objectsFetched += maintenance.objectsFetched
        diagnostic.objectsDeleted += maintenance.objectsDeleted
        diagnostic.maintenanceDeleted = maintenance.objectsDeleted
        try TranscriptPerformanceSignpost.interval("Cache save") {
            try context.save()
        }
    }

    @MainActor
    static func clearAll(in context: ModelContext) throws {
        for cachedSession in try context.fetch(FetchDescriptor<CachedSession>()) {
            context.delete(cachedSession)
        }

        for cachedMessage in try context.fetch(FetchDescriptor<CachedMessage>()) {
            context.delete(cachedMessage)
        }

        try context.save()
    }

    /// Deletes only the cached sessions and messages belonging to `serverURL`,
    /// leaving every other configured server's offline data intact (#18). Backs
    /// the Settings "Clear Offline Cache" action (active server) and the purge
    /// of a server's cache when it is removed, so a removed/reset server never
    /// leaves orphaned rows behind.
    @MainActor
    static func clearCache(for serverURL: URL, in context: ModelContext) throws {
        let serverURLString = serverURL.absoluteString

        let sessionDescriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { cachedSession in
                cachedSession.serverURLString == serverURLString
            }
        )
        for cachedSession in try context.fetch(sessionDescriptor) {
            context.delete(cachedSession)
        }

        let messageDescriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { cachedMessage in
                cachedMessage.serverURLString == serverURLString
            }
        )
        for cachedMessage in try context.fetch(messageDescriptor) {
            context.delete(cachedMessage)
        }

        try context.save()
    }

    @MainActor
    private static func performMaintenance(in context: ModelContext, now: Date) throws -> CacheMaintenanceDiagnostic {
        let expiredSessions = try deleteExpiredSessions(in: context, now: now)
        let expiredMessages = try deleteExpiredMessages(in: context, now: now)
        let evictedMessages = try evictOldestMessagesIfNeeded(in: context)
        return CacheMaintenanceDiagnostic(
            fetchCount: 3,
            objectsFetched: expiredSessions.fetched + expiredMessages.fetched + evictedMessages.fetched,
            objectsDeleted: expiredSessions.deleted + expiredMessages.deleted + evictedMessages.deleted
        )
    }

    @MainActor
    private static func deleteExpiredSessions(in context: ModelContext, now: Date) throws -> (fetched: Int, deleted: Int) {
        let descriptor = FetchDescriptor<CachedSession>()
        let fetched = try context.fetch(descriptor)
        let expiredSessions = fetched.filter { $0.expiresAt <= now }
        for session in expiredSessions {
            context.delete(session)
        }
        return (fetched.count, expiredSessions.count)
    }

    @MainActor
    private static func deleteExpiredMessages(in context: ModelContext, now: Date) throws -> (fetched: Int, deleted: Int) {
        let descriptor = FetchDescriptor<CachedMessage>()
        let fetched = try context.fetch(descriptor)
        let expiredMessages = fetched.filter { $0.expiresAt <= now }
        for message in expiredMessages {
            context.delete(message)
        }
        return (fetched.count, expiredMessages.count)
    }

    @MainActor
    private static func evictOldestMessagesIfNeeded(in context: ModelContext) throws -> (fetched: Int, deleted: Int) {
        let descriptor = FetchDescriptor<CachedMessage>()
        let messages = try context.fetch(descriptor)
        let overflowCount = messages.count - CachePolicy.maxMessages
        guard overflowCount > 0 else { return (messages.count, 0) }

        let messagesToEvict = messages
            .sorted { left, right in
                if left.cachedAt != right.cachedAt {
                    return left.cachedAt < right.cachedAt
                }

                if left.timestamp != right.timestamp {
                    return (left.timestamp ?? 0) < (right.timestamp ?? 0)
                }

                return left.sortIndex < right.sortIndex
            }
            .prefix(overflowCount)

        for message in messagesToEvict {
            context.delete(message)
        }
        return (messages.count, messagesToEvict.count)
    }

    @MainActor
    private static func cachedSession(cacheKey: String, in context: ModelContext) throws -> CachedSession? {
        var descriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { cachedSession in
                cachedSession.cacheKey == cacheKey
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @MainActor
    private static func cachedMessage(cacheKey: String, in context: ModelContext) throws -> CachedMessage? {
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { cachedMessage in
                cachedMessage.cacheKey == cacheKey
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

private extension SessionSummary {
    init(cachedSession: CachedSession) {
        sessionId = cachedSession.sessionID
        title = cachedSession.title
        workspace = cachedSession.workspace
        model = cachedSession.model
        modelProvider = cachedSession.modelProvider
        messageCount = cachedSession.messageCount
        createdAt = cachedSession.createdAt
        updatedAt = cachedSession.updatedAt
        lastMessageAt = cachedSession.lastMessageAt
        pinned = cachedSession.pinned
        archived = cachedSession.archived
        projectId = cachedSession.projectId
        profile = cachedSession.profile
        inputTokens = cachedSession.inputTokens
        outputTokens = cachedSession.outputTokens
        estimatedCost = cachedSession.estimatedCost
        activeStreamId = cachedSession.activeStreamId
        isStreaming = cachedSession.isStreaming
        isCliSession = cachedSession.isCliSession
        userMessageCount = cachedSession.userMessageCount
        hasPendingUserMessage = cachedSession.hasPendingUserMessage
        pendingStartedAt = cachedSession.pendingStartedAt
        worktreePath = cachedSession.worktreePath
        sourceTag = cachedSession.sourceTag
        rawSource = cachedSession.rawSource
        sessionSource = cachedSession.sessionSource
        sourceLabel = cachedSession.sourceLabel
        parentSessionId = cachedSession.parentSessionId
        relationshipType = cachedSession.relationshipType
        readOnly = cachedSession.readOnly
        isReadOnly = cachedSession.isReadOnly
        matchType = nil
    }
}

private extension ChatMessage {
    init(cachedMessage: CachedMessage) {
        let attachments: [MessageAttachment]?
        if let data = cachedMessage.attachmentsData {
            attachments = try? JSONDecoder().decode([MessageAttachment].self, from: data)
        } else {
            attachments = nil
        }
        let toolCalls: [JSONValue]?
        if let data = cachedMessage.toolCallsData {
            toolCalls = try? JSONDecoder().decode([JSONValue].self, from: data)
        } else {
            toolCalls = nil
        }
        let contentParts: [JSONValue]?
        if let data = cachedMessage.contentPartsData {
            contentParts = try? JSONDecoder().decode([JSONValue].self, from: data)
        } else {
            contentParts = nil
        }
        self.init(
            role: cachedMessage.role,
            content: cachedMessage.content,
            timestamp: cachedMessage.timestamp,
            messageId: cachedMessage.messageId,
            name: cachedMessage.name,
            toolCallId: cachedMessage.toolCallId,
            toolUseId: cachedMessage.toolUseId,
            toolCalls: toolCalls,
            contentParts: contentParts,
            reasoning: cachedMessage.reasoning,
            attachments: attachments
        )
    }
}
