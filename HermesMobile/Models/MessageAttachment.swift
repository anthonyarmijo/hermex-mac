import Foundation

struct MessageAttachment: Codable, Equatable, Sendable {
    let name: String?
    let path: String?
    let mime: String?
    let size: Int?
    let isImage: Bool?

    init(
        name: String? = nil,
        path: String? = nil,
        mime: String? = nil,
        size: Int? = nil,
        isImage: Bool? = nil
    ) {
        self.name = name
        self.path = path
        self.mime = mime
        self.size = size
        self.isImage = isImage
    }

    init(from decoder: Decoder) throws {
        // Tolerant decoding: upstream may store bare filenames (legacy) or
        // objects with unexpected field names / types. Never crash the parent
        // ChatMessage decode because of one malformed attachment.

        // Some old server data stores attachments as bare strings.
        if let bareName = try? decoder.singleValueContainer().decode(String.self) {
            self.name = bareName
            self.path = nil
            self.mime = nil
            self.size = nil
            self.isImage = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = container.decodeLossyStringIfPresent(forKey: .name)
            ?? container.decodeLossyStringIfPresent(forKey: .filename)
        self.path = container.decodeLossyStringIfPresent(forKey: .path)
        self.mime = container.decodeLossyStringIfPresent(forKey: .mime)
        self.size = container.decodeLossyIntIfPresent(forKey: .size)
        self.isImage = container.decodeLossyBoolIfPresent(forKey: .isImage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(mime, forKey: .mime)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(isImage, forKey: .isImage)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case filename
        case path
        case mime
        case size
        case isImage
    }
}

extension MessageAttachment {
    /// Stable identity for matching the *same* attachment across two
    /// representations — e.g. an optimistic local bubble against its
    /// server-reloaded copy. Uses the lowercased last path component (basename)
    /// of the first non-empty `name`/`path`, NOT the raw value: the server
    /// returns an attachment's `path` inconsistently on reload — usually a bare
    /// filename, occasionally the full upload path — so comparing raw values
    /// fails to match an optimistic bubble (full upload path) against its
    /// reloaded copy (bare filename). Voice notes are the live case: #330
    /// dropped their `[Attached files: <path>]` marker, which had silently
    /// backfilled the path on reload, so basename matching is now the only
    /// reliable key. Returns `nil` when the attachment carries no usable
    /// name or path.
    var identityKey: String? {
        let raw = [name, path]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let raw else { return nil }
        let lastComponent = URL(fileURLWithPath: raw).lastPathComponent
        let value = (lastComponent.isEmpty ? raw : lastComponent).lowercased()
        return value.isEmpty ? nil : value
    }
}

extension MessageAttachment {
    static func inferredFromAttachedFilesMarker(in content: String?) -> [MessageAttachment]? {
        guard let content,
              let marker = attachedFilesMarker(in: content)
        else {
            return nil
        }

        let inferredDirectory = marker.references
            .first(where: { $0.contains("/") })
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }

        let attachments = marker.references.map { reference in
            let name = displayName(for: reference)
            let path = inferredPath(for: reference, fallbackDirectory: inferredDirectory)
            return MessageAttachment(
                name: name,
                path: path,
                mime: nil,
                size: nil,
                isImage: isImageReference(reference)
            )
        }

        return attachments.isEmpty ? nil : attachments
    }

    /// Returns the message text with the trailing `[Attached files: …]` marker
    /// (and the blank-line separator it was appended after) removed, for the
    /// display layer to render. Reuses the same parser as attachment inference
    /// so the two can never disagree about what counts as a marker. The sent
    /// payload is built elsewhere and is unaffected by this display transform.
    static func contentWithoutAttachedFilesMarker(in content: String) -> String {
        guard let marker = attachedFilesMarker(in: content) else {
            return content
        }

        // The parser rejects any non-whitespace after the closing bracket, so
        // the marker is always a suffix; everything before it is the user's
        // typed message. Drop the trailing separator whitespace as well.
        var prefix = content[..<marker.range.lowerBound]
        while let last = prefix.last, last.isWhitespace {
            prefix = prefix.dropLast()
        }
        return String(prefix)
    }

    private static func attachedFilesMarker(
        in content: String
    ) -> (range: Range<String.Index>, references: [String])? {
        guard let markerRange = content.range(of: "[Attached files:", options: .backwards) else {
            return nil
        }

        let afterMarker = content[markerRange.upperBound...]
        guard let closeBracket = afterMarker.firstIndex(of: "]") else {
            return nil
        }

        let afterBracket = afterMarker[afterMarker.index(after: closeBracket)...]
        guard afterBracket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let references = afterMarker[..<closeBracket]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let markerEnd = afterMarker.index(after: closeBracket)
        return (markerRange.lowerBound..<markerEnd, references)
    }

    private static func displayName(for reference: String) -> String {
        let lastPathComponent = URL(fileURLWithPath: reference).lastPathComponent
        return lastPathComponent.isEmpty ? reference : lastPathComponent
    }

    private static func inferredPath(for reference: String, fallbackDirectory: String?) -> String? {
        if reference.contains("/") {
            return reference
        }

        guard isImageReference(reference),
              let fallbackDirectory,
              !fallbackDirectory.isEmpty
        else {
            return nil
        }

        return URL(fileURLWithPath: fallbackDirectory)
            .appendingPathComponent(reference)
            .path
    }

    private static func isImageReference(_ reference: String) -> Bool {
        let ext = URL(fileURLWithPath: reference).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"].contains(ext)
    }
}
