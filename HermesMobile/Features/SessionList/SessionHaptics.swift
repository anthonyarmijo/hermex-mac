import UIKit

enum SessionHapticFeedback: Equatable {
    case lightImpact
    case selection
    case warning
}

@MainActor
enum SessionHaptics {
    typealias Performer = @MainActor (SessionHapticFeedback) -> Void

    static func sessionCreated(isEnabled: Bool, performer: Performer = perform) {
        emit(.lightImpact, isEnabled: isEnabled, performer: performer)
    }

    static func pinStateChanged(isEnabled: Bool, performer: Performer = perform) {
        emit(.lightImpact, isEnabled: isEnabled, performer: performer)
    }

    static func archiveStateChanged(isEnabled: Bool, performer: Performer = perform) {
        emit(.lightImpact, isEnabled: isEnabled, performer: performer)
    }

    static func sessionDeleted(isEnabled: Bool, performer: Performer = perform) {
        emit(.warning, isEnabled: isEnabled, performer: performer)
    }

    static func sessionRenamed(isEnabled: Bool, performer: Performer = perform) {
        emit(.selection, isEnabled: isEnabled, performer: performer)
    }

    private static func emit(_ feedback: SessionHapticFeedback, isEnabled: Bool, performer: Performer) {
        guard isEnabled else { return }
        performer(feedback)
    }

    private static func perform(_ feedback: SessionHapticFeedback) {
        guard PlatformCapabilities.supportsHaptics else { return }

        switch feedback {
        case .lightImpact:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
