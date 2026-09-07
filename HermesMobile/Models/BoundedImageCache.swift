import CryptoKit
import Foundation
import ImageIO
import Observation
import UIKit

struct ImageCachePolicy: Sendable {
    let maximumEntries: Int
    let maximumCostBytes: Int
    let maximumPixelSize: Int

    // Up to 16 MiB for small attachment tiles and 64 MiB for retina inline
    // media. The byte limit, rather than entry count, governs large images.
    static let attachments = Self(maximumEntries: 96, maximumCostBytes: 16 * 1_024 * 1_024, maximumPixelSize: 512)
    static let media = Self(maximumEntries: 48, maximumCostBytes: 64 * 1_024 * 1_024, maximumPixelSize: 2_048)
}

struct PrivateImageCacheKey: Hashable, Sendable {
    let namespace: String
    let resource: String
    init(namespace: String, resource: String) {
        self.namespace = Self.digest(namespace)
        self.resource = Self.digest(resource)
    }
    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
@Observable
final class ImageCacheIdentity {
    private static let shared = ImageCacheIdentity()
    private var epoch = UUID()
    static func namespace(server: URL, session: String) -> String {
        PrivateImageCacheKey.digest("\(shared.epoch)|\(server.absoluteString)|\(session)")
    }
    static func invalidate() {
        // Change identity synchronously before a new authenticated view can
        // read a cache. Purging memory may then finish asynchronously.
        shared.epoch = UUID()
        Task {
            await AttachmentImageCache.shared.removeAll()
            await TranscriptMediaImageCache.shared.removeAll()
            await TranscriptLinkPreviewCache.shared.removeAll()
        }
    }
}

actor BoundedImageCache {
    private struct Entry {
        let image: UIImage
        let cost: Int
    }
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<UIImage?, Never>]
    }
    private let policy: ImageCachePolicy
    private var entries: [PrivateImageCacheKey: Entry] = [:]
    private var recency: [PrivateImageCacheKey] = []
    private var flights: [PrivateImageCacheKey: Flight] = [:]
    private var costBytes = 0
    private var hits = 0
    private var misses = 0
    private var evictions = 0
    private var memoryWarningObserver: NSObjectProtocol?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(policy: ImageCachePolicy) {
        self.policy = policy
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
        for flight in flights.values { flight.task.cancel(); flight.waiters.values.forEach { $0.resume(returning: nil) } }
    }

    func image(namespace: String, resource: String, load: @escaping () async -> Data?) async -> UIImage? {
        observeMemoryPressureIfNeeded()
        guard !Task.isCancelled else { return nil }
        // Unscoped callers may load, but cannot reuse authenticated images across contexts.
        let key = PrivateImageCacheKey(namespace: namespace.isEmpty ? UUID().uuidString : namespace, resource: resource)
        if let entry = entries[key] {
            hits += 1
            TranscriptPerformanceSignpost.event("Image cache lookup hit")
            touch(key)
            return entry.image
        }
        let waiter = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                if flights[key] != nil {
                    hits += 1
                    flights[key]?.waiters[waiter] = continuation
                    return
                }
                misses += 1
                TranscriptPerformanceSignpost.event("Image cache lookup miss")
                let id = UUID()
                let maximum = policy.maximumPixelSize
                let work = Task { [weak self] in
                    let signpost = TranscriptPerformanceSignpost.begin("Image load")
                    let data = await load()
                    TranscriptPerformanceSignpost.end("Image load", signpostID: signpost, count: data?.count ?? 0)
                    let image: UIImage?
                    if let data, !Task.isCancelled {
                        image = await Self.downsample(data, maximum: maximum)
                    } else { image = nil }
                    guard !Task.isCancelled else { return }
                    await self?.complete(key, id: id, image: image)
                }
                flights[key] = Flight(id: id, task: work, waiters: [waiter: continuation])
            }
        } onCancel: {
            Task { await self.cancelWaiter(key, waiter: waiter) }
        }
    }

    private func cancelWaiter(_ key: PrivateImageCacheKey, waiter: UUID) {
        guard let continuation = flights[key]?.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(returning: nil)
        if flights[key]?.waiters.isEmpty == true {
            flights.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func complete(_ key: PrivateImageCacheKey, id: UUID, image: UIImage?) {
        guard let flight = flights[key], flight.id == id else { return }
        flights.removeValue(forKey: key)
        if let image, let cgImage = image.cgImage {
            let cost = cgImage.bytesPerRow * cgImage.height
            if cost <= policy.maximumCostBytes, policy.maximumEntries > 0 {
                if let old = entries.removeValue(forKey: key) { costBytes -= old.cost }
                entries[key] = Entry(image: image, cost: cost)
                costBytes += cost
                touch(key)
                while (costBytes > policy.maximumCostBytes || entries.count > policy.maximumEntries), let oldest = recency.first {
                    recency.removeFirst()
                    if let old = entries.removeValue(forKey: oldest) { costBytes -= old.cost; evictions += 1 }
                }
            }
        }
        for continuation in flight.waiters.values { continuation.resume(returning: image) }
    }

    private func touch(_ key: PrivateImageCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    func remove(namespace: String) {
        let namespace = PrivateImageCacheKey.digest(namespace)
        for key in Array(entries.keys) where key.namespace == namespace {
            costBytes -= entries.removeValue(forKey: key)!.cost
        }
        recency.removeAll { $0.namespace == namespace }
        for key in Array(flights.keys) where key.namespace == namespace {
            guard let flight = flights.removeValue(forKey: key) else { continue }
            flight.task.cancel()
            flight.waiters.values.forEach { $0.resume(returning: nil) }
        }
    }

    func removeAll() {
        entries.removeAll()
        recency.removeAll()
        costBytes = 0
        let pending = flights.values
        flights.removeAll()
        for flight in pending {
            flight.task.cancel()
            flight.waiters.values.forEach { $0.resume(returning: nil) }
        }
    }

    func resetForDiagnostics() {
        removeAll()
        hits = 0
        misses = 0
        evictions = 0
    }

    func diagnosticSnapshot() -> ImageCacheDiagnosticSnapshot {
        ImageCacheDiagnosticSnapshot(entries: entries.count, costBytes: costBytes, hits: hits, misses: misses,
                                     evictions: evictions, inFlight: flights.count)
    }

    nonisolated private static func downsample(_ data: Data, maximum: Int) async -> UIImage? {
        await withTaskGroup(of: UIImage?.self) { group in
            group.addTask(priority: .userInitiated) {
                guard !Task.isCancelled, maximum > 0,
                      let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
                else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximum
                ]
                let signpost = TranscriptPerformanceSignpost.begin("Image decode")
                defer { TranscriptPerformanceSignpost.end("Image decode", signpostID: signpost, count: data.count) }
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), !Task.isCancelled else { return nil }
                // Keep pixels and alpha directly; no intermediate JPEG or second decode.
                return UIImage(cgImage: image)
            }
            let image = await group.next() ?? nil
            return Task.isCancelled ? nil : image
        }
    }
}
