import Foundation
import Darwin
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
    var reconciliationNanoseconds: UInt64 = 0
    var encodingNanoseconds: UInt64 = 0
    var maintenanceNanoseconds: UInt64 = 0
    var saveNanoseconds: UInt64 = 0
    var totalNanoseconds: UInt64 = 0
    var coalescedSnapshots = 0
    var skippedStaleGeneration = false
}

private struct CacheMaintenanceDiagnostic: Sendable {
    let fetchCount: Int
    let objectsFetched: Int
    let objectsDeleted: Int
}

enum CacheWriteScope: Hashable, Sendable {
    case sessions(serverURLString: String)
    case messages(serverURLString: String, sessionID: String)

    var serverURLString: String {
        switch self {
        case .sessions(let serverURLString), .messages(let serverURLString, _):
            return serverURLString
        }
    }
}

struct CacheSessionListSnapshot: Sendable {
    let serverURLString: String
    let sessions: [SessionSummary]
    let cachedAt: Date
    let generation: UUID

    init(serverURL: URL, sessions: [SessionSummary], cachedAt: Date = Date(), generation: UUID) {
        serverURLString = serverURL.absoluteString
        self.sessions = sessions
        self.cachedAt = cachedAt
        self.generation = generation
    }
}

struct CacheSessionSnapshot: Sendable {
    let serverURLString: String
    let session: SessionSummary
    let cachedAt: Date
    let generation: UUID

    init(serverURL: URL, session: SessionSummary, cachedAt: Date = Date(), generation: UUID) {
        serverURLString = serverURL.absoluteString
        self.session = session
        self.cachedAt = cachedAt
        self.generation = generation
    }
}

struct CacheMessageListSnapshot: Sendable {
    let serverURLString: String
    let sessionID: String
    let messages: [ChatMessage]
    let cachedAt: Date
    let generation: UUID

    init(
        serverURL: URL,
        sessionID: String,
        messages: [ChatMessage],
        cachedAt: Date = Date(),
        generation: UUID
    ) {
        serverURLString = serverURL.absoluteString
        self.sessionID = sessionID
        self.messages = messages
        self.cachedAt = cachedAt
        self.generation = generation
    }
}

struct CachedMessageValueSnapshot: Sendable {
    let role: String?
    let content: String?
    let timestamp: Double?
    let messageID: String?
    let name: String?
    let toolCallID: String?
    let toolUseID: String?
    let toolCallsData: Data?
    let contentPartsData: Data?
    let reasoning: String?
    let attachmentsData: Data?

    init(message: ChatMessage, encoder: JSONEncoder) {
        role = message.role
        content = message.content
        timestamp = message.timestamp
        messageID = message.messageId
        name = message.name
        toolCallID = message.toolCallId
        toolUseID = message.toolUseId
        toolCallsData = Self.encode(message.toolCalls, using: encoder)
        contentPartsData = Self.encode(message.contentParts, using: encoder)
        reasoning = message.reasoning
        attachmentsData = Self.encode(message.attachments, using: encoder)
    }

    private static func encode<Value: Encodable>(_ values: [Value]?, using encoder: JSONEncoder) -> Data? {
        guard let values, !values.isEmpty else { return nil }
        return try? encoder.encode(values)
    }
}

enum CacheWriteRequest: Sendable {
    case replaceSessions(CacheSessionListSnapshot)
    case upsertSession(CacheSessionSnapshot)
    case replaceMessages(CacheMessageListSnapshot)
    case clearServer(serverURLString: String)
    case clearAll
    case maintenance(now: Date)

    fileprivate var scope: CacheWriteScope? {
        switch self {
        case .replaceSessions(let snapshot):
            return .sessions(serverURLString: snapshot.serverURLString)
        case .replaceMessages(let snapshot):
            return .messages(serverURLString: snapshot.serverURLString, sessionID: snapshot.sessionID)
        case .upsertSession, .clearServer, .clearAll, .maintenance:
            return nil
        }
    }

    fileprivate var generation: UUID? {
        switch self {
        case .replaceSessions(let snapshot): snapshot.generation
        case .replaceMessages(let snapshot): snapshot.generation
        case .upsertSession, .clearServer, .clearAll, .maintenance: nil
        }
    }

    fileprivate var coalescingScope: CacheWriteScope? {
        switch self {
        case .replaceSessions, .replaceMessages:
            return scope
        case .upsertSession, .clearServer, .clearAll, .maintenance:
            return nil
        }
    }

    fileprivate func isBarrier(for scope: CacheWriteScope) -> Bool {
        switch self {
        case .clearAll, .maintenance:
            return true
        case .clearServer(let serverURLString):
            return scope.serverURLString == serverURLString
        case .upsertSession(let snapshot):
            return scope == .sessions(serverURLString: snapshot.serverURLString)
        case .replaceSessions, .replaceMessages:
            return false
        }
    }
}

protocol CacheWriting: Sendable {
    func activate(scope: CacheWriteScope, generation: UUID) async
    func write(_ request: CacheWriteRequest) async throws -> CacheWriteDiagnosticSnapshot
}

protocol CachePersistenceWriting: Sendable {
    func execute(_ request: CacheWriteRequest) async throws -> CacheWriteDiagnosticSnapshot
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

/// Serializes all persistence mutations for a model container. Pending full
/// snapshots for the same scope are coalesced, while semantic mutations and
/// clear/maintenance requests remain ordering barriers.
actor CacheWriter: CacheWriting {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<CacheWriteDiagnosticSnapshot, Error>
    }

    private struct PendingWrite {
        var request: CacheWriteRequest
        var waiters: [Waiter]
        var coalescedSnapshots: Int
    }

    private let persistence: any CachePersistenceWriting
    private var activeGenerations: [CacheWriteScope: UUID] = [:]
    private var invalidatedScopes: Set<CacheWriteScope> = []
    private var pendingWrites: [PendingWrite] = []
    private var worker: Task<Void, Never>?

    init(modelContainer: ModelContainer) {
        persistence = CachePersistenceWriter(modelContainer: modelContainer)
    }

    init(persistence: any CachePersistenceWriting) {
        self.persistence = persistence
    }

#if DEBUG
    func pendingWriteCountForTesting() -> Int {
        pendingWrites.count
    }
#endif

    func activate(scope: CacheWriteScope, generation: UUID) {
        activeGenerations[scope] = generation
        invalidatedScopes.remove(scope)

        var retained: [PendingWrite] = []
        for pending in pendingWrites {
            guard pending.request.scope == scope,
                  pending.request.generation != generation
            else {
                retained.append(pending)
                continue
            }

            var diagnostic = CacheWriteDiagnosticSnapshot()
            diagnostic.skippedStaleGeneration = true
            for waiter in pending.waiters {
                waiter.continuation.resume(returning: diagnostic)
            }
        }
        pendingWrites = retained
    }

    func write(_ request: CacheWriteRequest) async throws -> CacheWriteDiagnosticSnapshot {
        try Task.checkCancellation()
        invalidateScopesIfNeeded(for: request)

        if shouldSkipForStaleGeneration(request) {
            var diagnostic = CacheWriteDiagnosticSnapshot()
            diagnostic.skippedStaleGeneration = true
            return diagnostic
        }

        let waiterID = UUID()
        let diagnostic = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(
                    request,
                    waiter: Waiter(id: waiterID, continuation: continuation)
                )
                startWorkerIfNeeded()
            }
        } onCancel: {
            Task { await self.cancelPendingWaiter(waiterID) }
        }
        try Task.checkCancellation()
        return diagnostic
    }

    private func enqueue(_ request: CacheWriteRequest, waiter: Waiter) {
        var newPending = PendingWrite(request: request, waiters: [waiter], coalescedSnapshots: 0)

        if let scope = request.coalescingScope,
           let previousIndex = coalesciblePendingIndex(for: scope) {
            let previous = pendingWrites.remove(at: previousIndex)
            newPending.waiters.insert(contentsOf: previous.waiters, at: 0)
            newPending.coalescedSnapshots = previous.coalescedSnapshots + 1
        }

        pendingWrites.append(newPending)
    }

    private func coalesciblePendingIndex(for scope: CacheWriteScope) -> Int? {
        for index in pendingWrites.indices.reversed() {
            let pending = pendingWrites[index]
            if pending.request.isBarrier(for: scope) {
                return nil
            }
            if pending.request.coalescingScope == scope {
                return index
            }
        }
        return nil
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !pendingWrites.isEmpty {
            let pending = pendingWrites.removeFirst()

            if shouldSkipForStaleGeneration(pending.request) {
                var diagnostic = CacheWriteDiagnosticSnapshot()
                diagnostic.coalescedSnapshots = pending.coalescedSnapshots
                diagnostic.skippedStaleGeneration = true
                for waiter in pending.waiters {
                    waiter.continuation.resume(returning: diagnostic)
                }
                continue
            }

            do {
                var diagnostic = try await persistence.execute(pending.request)
                diagnostic.coalescedSnapshots = pending.coalescedSnapshots
                for waiter in pending.waiters {
                    waiter.continuation.resume(returning: diagnostic)
                }
            } catch {
                for waiter in pending.waiters {
                    waiter.continuation.resume(throwing: error)
                }
            }
        }

        worker = nil
        if !pendingWrites.isEmpty {
            startWorkerIfNeeded()
        }
    }

    private func cancelPendingWaiter(_ waiterID: UUID) {
        for index in pendingWrites.indices {
            guard let waiterIndex = pendingWrites[index].waiters.firstIndex(where: { $0.id == waiterID }) else {
                continue
            }

            let waiter = pendingWrites[index].waiters.remove(at: waiterIndex)
            waiter.continuation.resume(throwing: CancellationError())
            if pendingWrites[index].waiters.isEmpty {
                pendingWrites.remove(at: index)
            }
            return
        }
    }

    private func shouldSkipForStaleGeneration(_ request: CacheWriteRequest) -> Bool {
        guard let scope = request.scope, let generation = request.generation else { return false }
        if invalidatedScopes.contains(scope) { return true }

        if let activeGeneration = activeGenerations[scope] {
            return activeGeneration != generation
        }

        activeGenerations[scope] = generation
        return false
    }

    private func invalidateScopesIfNeeded(for request: CacheWriteRequest) {
        switch request {
        case .clearServer(let serverURLString):
            invalidatedScopes.formUnion(activeGenerations.keys.filter {
                $0.serverURLString == serverURLString
            })
        case .clearAll:
            invalidatedScopes.formUnion(activeGenerations.keys)
        case .replaceSessions, .upsertSession, .replaceMessages, .maintenance:
            break
        }
    }
}

/// Owns the only SwiftData ModelContext used for cache mutations. All values
/// crossing this boundary are immutable Sendable snapshots.
@ModelActor
actor CachePersistenceWriter: CachePersistenceWriting {
    private static let maintenanceInterval: TimeInterval = 60
    static let maintenanceWriteThreshold = 20

    private var lastMaintenanceAt: Date?
    private var writesSinceMaintenance = 0

    func execute(_ request: CacheWriteRequest) async throws -> CacheWriteDiagnosticSnapshot {
        try Task.checkCancellation()
        var diagnostic = CacheWriteDiagnosticSnapshot(ranOnMainActor: pthread_main_np() != 0)
        let totalStart = ContinuousClock.now
        let totalSignpost = TranscriptPerformanceSignpost.begin("Cache write total")
        defer {
            TranscriptPerformanceSignpost.end(
                "Cache write total",
                signpostID: totalSignpost,
                count: request.itemCount
            )
        }

        do {
            switch request {
            case .replaceSessions(let snapshot):
                try runAutomaticMaintenance(now: snapshot.cachedAt, diagnostic: &diagnostic)
                let start = ContinuousClock.now
                try reconcileSessions(snapshot, diagnostic: &diagnostic)
                diagnostic.reconciliationNanoseconds = Self.nanoseconds(start.duration(to: .now))
                try save(diagnostic: &diagnostic)

            case .upsertSession(let snapshot):
                try runAutomaticMaintenance(now: snapshot.cachedAt, diagnostic: &diagnostic)
                let start = ContinuousClock.now
                try upsertSession(snapshot, diagnostic: &diagnostic)
                diagnostic.reconciliationNanoseconds = Self.nanoseconds(start.duration(to: .now))
                try save(diagnostic: &diagnostic)

            case .replaceMessages(let snapshot):
                try runAutomaticMaintenance(
                    now: snapshot.cachedAt,
                    diagnostic: &diagnostic,
                    enforcesMessageLimit: false
                )
                try reconcileMessages(snapshot, diagnostic: &diagnostic)
                try enforceMessageLimit(diagnostic: &diagnostic)
                try save(diagnostic: &diagnostic)

            case .clearServer(let serverURLString):
                try clearServer(serverURLString)
                try save(diagnostic: &diagnostic)

            case .clearAll:
                try modelContext.delete(model: CachedSession.self)
                try modelContext.delete(model: CachedMessage.self)
                try save(diagnostic: &diagnostic)

            case .maintenance(let now):
                try performMaintenance(now: now, diagnostic: &diagnostic)
                try save(diagnostic: &diagnostic)
            }
        } catch {
            modelContext.rollback()
            throw error
        }

        diagnostic.totalNanoseconds = Self.nanoseconds(totalStart.duration(to: .now))
        return diagnostic
    }

    private func reconcileSessions(
        _ snapshot: CacheSessionListSnapshot,
        diagnostic: inout CacheWriteDiagnosticSnapshot
    ) throws {
        let signpost = TranscriptPerformanceSignpost.begin("Cache write reconciliation")
        defer {
            TranscriptPerformanceSignpost.end(
                "Cache write reconciliation",
                signpostID: signpost,
                count: snapshot.sessions.count
            )
        }

        let serverURLString = snapshot.serverURLString
        let descriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { $0.serverURLString == serverURLString }
        )
        diagnostic.fetchCount += 1
        let existing = try modelContext.fetch(descriptor)
        diagnostic.objectsFetched += existing.count
        var existingByKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.cacheKey, $0) })

        for session in snapshot.sessions where session.archived != true {
            try Task.checkCancellation()
            guard let sessionID = session.sessionId else { continue }
            let key = CachedSession.cacheKey(serverURLString: serverURLString, sessionID: sessionID)
            if let cached = existingByKey.removeValue(forKey: key) {
                cached.apply(session, cachedAt: snapshot.cachedAt)
                diagnostic.objectsUpdated += 1
            } else {
                modelContext.insert(CachedSession(
                    serverURLString: serverURLString,
                    session: session,
                    cachedAt: snapshot.cachedAt
                ))
                diagnostic.objectsInserted += 1
            }
        }

        for stale in existingByKey.values {
            modelContext.delete(stale)
            diagnostic.objectsDeleted += 1
        }
    }

    private func upsertSession(
        _ snapshot: CacheSessionSnapshot,
        diagnostic: inout CacheWriteDiagnosticSnapshot
    ) throws {
        guard let sessionID = snapshot.session.sessionId else { return }
        let serverURLString = snapshot.serverURLString
        let key = CachedSession.cacheKey(serverURLString: serverURLString, sessionID: sessionID)
        var descriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        descriptor.fetchLimit = 1
        diagnostic.fetchCount += 1
        let cached = try modelContext.fetch(descriptor).first
        diagnostic.objectsFetched += cached == nil ? 0 : 1

        if snapshot.session.archived == true {
            if let cached {
                modelContext.delete(cached)
                diagnostic.objectsDeleted += 1
            }
        } else if let cached {
            cached.apply(snapshot.session, cachedAt: snapshot.cachedAt)
            diagnostic.objectsUpdated += 1
        } else {
            modelContext.insert(CachedSession(
                serverURLString: serverURLString,
                session: snapshot.session,
                cachedAt: snapshot.cachedAt
            ))
            diagnostic.objectsInserted += 1
        }
    }

    private func reconcileMessages(
        _ snapshot: CacheMessageListSnapshot,
        diagnostic: inout CacheWriteDiagnosticSnapshot
    ) throws {
        let encodingStart = ContinuousClock.now
        let encodedMessages: [(key: String, value: CachedMessageValueSnapshot, sortIndex: Int)] = try
            TranscriptPerformanceSignpost.interval("Cache write encoding", count: snapshot.messages.count) {
                let encoder = JSONEncoder()
                return try snapshot.messages.enumerated().map { sortIndex, message in
                    if sortIndex.isMultiple(of: 128) { try Task.checkCancellation() }
                    return (
                        CachedMessage.cacheKey(
                            serverURLString: snapshot.serverURLString,
                            sessionID: snapshot.sessionID,
                            message: message,
                            sortIndex: sortIndex
                        ),
                        CachedMessageValueSnapshot(message: message, encoder: encoder),
                        sortIndex
                    )
                }
            }
        diagnostic.encodingNanoseconds = Self.nanoseconds(encodingStart.duration(to: .now))

        let reconciliationStart = ContinuousClock.now
        let signpost = TranscriptPerformanceSignpost.begin("Cache write reconciliation")
        defer {
            diagnostic.reconciliationNanoseconds = Self.nanoseconds(reconciliationStart.duration(to: .now))
            TranscriptPerformanceSignpost.end(
                "Cache write reconciliation",
                signpostID: signpost,
                count: snapshot.messages.count
            )
        }

        let serverURLString = snapshot.serverURLString
        let sessionID = snapshot.sessionID
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate {
                $0.serverURLString == serverURLString && $0.sessionID == sessionID
            }
        )
        diagnostic.fetchCount += 1
        let existing = try modelContext.fetch(descriptor)
        diagnostic.objectsFetched += existing.count
        var existingByKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.cacheKey, $0) })

        for encoded in encodedMessages {
            if encoded.sortIndex.isMultiple(of: 128) { try Task.checkCancellation() }
            if let cached = existingByKey.removeValue(forKey: encoded.key) {
                cached.apply(encoded.value, sortIndex: encoded.sortIndex, cachedAt: snapshot.cachedAt)
                diagnostic.objectsUpdated += 1
            } else {
                modelContext.insert(CachedMessage(
                    cacheKey: encoded.key,
                    serverURLString: serverURLString,
                    sessionID: sessionID,
                    value: encoded.value,
                    sortIndex: encoded.sortIndex,
                    cachedAt: snapshot.cachedAt
                ))
                diagnostic.objectsInserted += 1
            }
        }

        for stale in existingByKey.values {
            modelContext.delete(stale)
            diagnostic.objectsDeleted += 1
        }
    }

    private func runAutomaticMaintenance(
        now: Date,
        diagnostic: inout CacheWriteDiagnosticSnapshot,
        enforcesMessageLimit: Bool = true
    ) throws {
        writesSinceMaintenance += 1
        let intervalElapsed = lastMaintenanceAt.map {
            now.timeIntervalSince($0) >= Self.maintenanceInterval
        } ?? true
        guard intervalElapsed || writesSinceMaintenance >= Self.maintenanceWriteThreshold else { return }
        try performMaintenance(
            now: now,
            diagnostic: &diagnostic,
            enforcesMessageLimit: enforcesMessageLimit
        )
    }

    private func performMaintenance(
        now: Date,
        diagnostic: inout CacheWriteDiagnosticSnapshot,
        enforcesMessageLimit: Bool = true
    ) throws {
        let start = ContinuousClock.now
        try TranscriptPerformanceSignpost.interval("Cache maintenance") {
            let expiredSessionPredicate = #Predicate<CachedSession> { $0.expiresAt <= now }
            let expiredMessagePredicate = #Predicate<CachedMessage> { $0.expiresAt <= now }

            diagnostic.fetchCount += 2
            let expiredSessionCount = try modelContext.fetchCount(
                FetchDescriptor<CachedSession>(predicate: expiredSessionPredicate)
            )
            let expiredMessageCount = try modelContext.fetchCount(
                FetchDescriptor<CachedMessage>(predicate: expiredMessagePredicate)
            )
            try modelContext.delete(model: CachedSession.self, where: expiredSessionPredicate)
            try modelContext.delete(model: CachedMessage.self, where: expiredMessagePredicate)
            diagnostic.objectsDeleted += expiredSessionCount + expiredMessageCount
            diagnostic.maintenanceDeleted += expiredSessionCount + expiredMessageCount

            if enforcesMessageLimit {
                try enforceMessageLimit(diagnostic: &diagnostic)
            }
        }
        diagnostic.maintenanceNanoseconds += Self.nanoseconds(start.duration(to: .now))
        lastMaintenanceAt = now
        writesSinceMaintenance = 0
    }

    private func enforceMessageLimit(diagnostic: inout CacheWriteDiagnosticSnapshot) throws {
        modelContext.processPendingChanges()
        diagnostic.fetchCount += 1
        let totalCount = try modelContext.fetchCount(FetchDescriptor<CachedMessage>())
        let overflowCount = totalCount - CachePolicy.maxMessages
        guard overflowCount > 0 else { return }

        var descriptor = FetchDescriptor<CachedMessage>(
            sortBy: [
                SortDescriptor(\.cachedAt),
                SortDescriptor(\.timestamp),
                SortDescriptor(\.sortIndex),
                SortDescriptor(\.cacheKey)
            ]
        )
        descriptor.fetchLimit = overflowCount
        diagnostic.fetchCount += 1
        let evicted = try modelContext.fetch(descriptor)
        diagnostic.objectsFetched += evicted.count
        for message in evicted {
            modelContext.delete(message)
        }
        diagnostic.objectsDeleted += evicted.count
        diagnostic.maintenanceDeleted += evicted.count
    }

    private func clearServer(_ serverURLString: String) throws {
        let sessions = #Predicate<CachedSession> { $0.serverURLString == serverURLString }
        let messages = #Predicate<CachedMessage> { $0.serverURLString == serverURLString }
        try modelContext.delete(model: CachedSession.self, where: sessions)
        try modelContext.delete(model: CachedMessage.self, where: messages)
    }

    private func save(diagnostic: inout CacheWriteDiagnosticSnapshot) throws {
        let start = ContinuousClock.now
        try TranscriptPerformanceSignpost.interval("Cache save") {
            try modelContext.save()
        }
        diagnostic.saveNanoseconds = Self.nanoseconds(start.duration(to: .now))
    }

    private static func nanoseconds(_ duration: Duration) -> UInt64 {
        let components = duration.components
        return UInt64(max(components.seconds, 0)) * 1_000_000_000
            + UInt64(max(components.attoseconds, 0)) / 1_000_000_000
    }
}

private extension CacheWriteRequest {
    var itemCount: Int {
        switch self {
        case .replaceSessions(let snapshot): snapshot.sessions.count
        case .upsertSession: 1
        case .replaceMessages(let snapshot): snapshot.messages.count
        case .clearServer, .clearAll, .maintenance: 0
        }
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
