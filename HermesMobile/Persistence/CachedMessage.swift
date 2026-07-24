import Foundation
import SwiftData

@Model
final class CachedMessage {
    @Attribute(.unique) var cacheKey: String
    var serverURLString: String
    var sessionID: String
    var sortIndex: Int
    var role: String?
    var content: String?
    var timestamp: Double?
    var messageId: String?
    var name: String?
    var toolCallId: String?
    var toolUseId: String?
    var toolCallsData: Data?
    var contentPartsData: Data?
    var reasoning: String?
    var attachmentsData: Data?
    var cachedAt: Date
    var expiresAt: Date

    init(
        serverURLString: String,
        sessionID: String,
        message: ChatMessage,
        sortIndex: Int,
        cachedAt: Date = Date()
    ) {
        let cacheKey = Self.cacheKey(
            serverURLString: serverURLString,
            sessionID: sessionID,
            message: message,
            sortIndex: sortIndex
        )
        let value = CachedMessageValueSnapshot(message: message, encoder: JSONEncoder())
        self.cacheKey = cacheKey
        self.serverURLString = serverURLString
        self.sessionID = sessionID
        self.sortIndex = sortIndex
        self.cachedAt = cachedAt
        self.expiresAt = cachedAt.addingTimeInterval(CachePolicy.ttl)
        apply(value, sortIndex: sortIndex, cachedAt: cachedAt)
    }

    init(
        cacheKey: String,
        serverURLString: String,
        sessionID: String,
        value: CachedMessageValueSnapshot,
        sortIndex: Int,
        cachedAt: Date
    ) {
        self.cacheKey = cacheKey
        self.serverURLString = serverURLString
        self.sessionID = sessionID
        self.sortIndex = sortIndex
        self.cachedAt = cachedAt
        self.expiresAt = cachedAt.addingTimeInterval(CachePolicy.ttl)
        apply(value, sortIndex: sortIndex, cachedAt: cachedAt)
    }

    static func cacheKey(
        serverURLString: String,
        sessionID: String,
        message: ChatMessage,
        sortIndex: Int
    ) -> String {
        let messagePart = message.messageId ?? "\(sortIndex)-\(message.timestamp ?? 0)"
        return "\(serverURLString)|session|\(sessionID)|message|\(messagePart)"
    }

    func apply(_ message: ChatMessage, sortIndex: Int, cachedAt: Date = Date()) {
        apply(
            CachedMessageValueSnapshot(message: message, encoder: JSONEncoder()),
            sortIndex: sortIndex,
            cachedAt: cachedAt
        )
    }

    func apply(_ value: CachedMessageValueSnapshot, sortIndex: Int, cachedAt: Date = Date()) {
        self.sortIndex = sortIndex
        role = value.role
        content = value.content
        timestamp = value.timestamp
        messageId = value.messageID
        name = value.name
        toolCallId = value.toolCallID
        toolUseId = value.toolUseID
        toolCallsData = value.toolCallsData
        contentPartsData = value.contentPartsData
        reasoning = value.reasoning
        attachmentsData = value.attachmentsData
        self.cachedAt = cachedAt
        expiresAt = cachedAt.addingTimeInterval(CachePolicy.ttl)
    }
}
