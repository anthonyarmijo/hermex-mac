import Foundation
import UIKit

struct TranscriptLinkPreviewSnapshot: Equatable {
    let title: String?
    let displayURL: URL?
    let imageData: Data?

    init(title: String? = nil, displayURL: URL? = nil, imageData: Data? = nil) {
        self.title = Self.nonEmpty(title)
        self.displayURL = displayURL
        self.imageData = imageData
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

actor TranscriptLinkPreviewCache {
    static let shared = TranscriptLinkPreviewCache()

    private let maximumEntryCount: Int
    private var entries: [String: TranscriptLinkPreviewSnapshot] = [:]
    private var recency: [String] = []
    private let maximumCostBytes: Int
    private var costBytes = 0
    private var memoryWarningObserver: NSObjectProtocol?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(maximumEntryCount: Int = 96, maximumCostBytes: Int = 8 * 1_024 * 1_024) {
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.maximumCostBytes = max(0, maximumCostBytes)
    }

    private func observeMemoryPressureIfNeeded() {
        guard memoryWarningObserver == nil else { return }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in Task { await self?.removeAll() } }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        pressure.setEventHandler { [weak self] in Task { await self?.removeAll() } }
        pressure.resume()
        memoryPressureSource = pressure
    }

    deinit {
        memoryPressureSource?.cancel()
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    private func cost(_ snapshot: TranscriptLinkPreviewSnapshot) -> Int {
        (snapshot.imageData?.count ?? 0) + (snapshot.title?.utf8.count ?? 0)
            + (snapshot.displayURL?.absoluteString.utf8.count ?? 0)
    }

    func diagnosticCostBytes() -> Int { costBytes }

    func snapshot(for url: URL) -> TranscriptLinkPreviewSnapshot? {
        guard let key = Self.cacheKey(for: url).map(PrivateImageCacheKey.digest),
              let snapshot = entries[key]
        else {
            return nil
        }

        markRecentlyUsed(key)
        return snapshot
    }

    func store(_ snapshot: TranscriptLinkPreviewSnapshot, for url: URL) {
        observeMemoryPressureIfNeeded()
        guard let key = Self.cacheKey(for: url).map(PrivateImageCacheKey.digest) else { return }

        if let old = entries.removeValue(forKey: key) { costBytes -= cost(old) }
        recency.removeAll { $0 == key }
        let newCost = cost(snapshot)
        guard newCost <= maximumCostBytes else { return }
        entries[key] = snapshot
        costBytes += newCost
        markRecentlyUsed(key)
        evictIfNeeded()
    }

    func removeAll() {
        entries.removeAll()
        recency.removeAll()
        costBytes = 0
    }

    static func cacheKey(for url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty
        else {
            return nil
        }

        components.scheme = scheme
        components.host = host
        components.fragment = nil

        if scheme == "http", components.port == 80 {
            components.port = nil
        } else if scheme == "https", components.port == 443 {
            components.port = nil
        }

        return components.url?.absoluteString
    }

    private func markRecentlyUsed(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func evictIfNeeded() {
        while entries.count > maximumEntryCount || costBytes > maximumCostBytes, let oldestKey = recency.first {
            recency.removeFirst()
            if let old = entries.removeValue(forKey: oldestKey) { costBytes -= cost(old) }
        }
    }
}
