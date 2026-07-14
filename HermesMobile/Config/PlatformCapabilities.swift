/// Compile-time platform policy for features that exist on iPhone and iPad but
/// have no useful or supported Mac Catalyst implementation.
enum PlatformCapabilities {
    #if targetEnvironment(macCatalyst)
    static let isMacCatalyst = true
    static let supportsDedicatedSettingsWindow = true
    static let usesNativeSessionFileExporter = true
    static let supportsHaptics = false
    static let supportsCameraCapture = false
    static let supportsAlternateAppIcons = false
    static let supportsLiveActivities = false
    static let supportsIOSShareExtension = false
    #else
    static let isMacCatalyst = false
    static let supportsDedicatedSettingsWindow = false
    static let usesNativeSessionFileExporter = false
    static let supportsHaptics = true
    static let supportsCameraCapture = true
    static let supportsAlternateAppIcons = true
    static let supportsLiveActivities = true
    static let supportsIOSShareExtension = true
    #endif
}
