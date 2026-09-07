import XCTest
import UIKit
import UserNotifications
@testable import HermesMobile

final class PlatformCapabilitiesTests: XCTestCase {
    func testMacSceneIdentifiersStayStableForWindowRestoration() {
        XCTAssertEqual(HermexSceneID.settings, "settings")
        XCTAssertEqual(HermexSceneID.settingsValue, "singleton")
    }

    func testCapabilitiesMatchCurrentPlatform() {
        #if targetEnvironment(macCatalyst)
        XCTAssertTrue(PlatformCapabilities.isMacCatalyst)
        XCTAssertTrue(PlatformCapabilities.supportsDedicatedSettingsWindow)
        XCTAssertTrue(PlatformCapabilities.usesNativeSessionFileExporter)
        XCTAssertFalse(PlatformCapabilities.supportsHaptics)
        XCTAssertFalse(PlatformCapabilities.supportsCameraCapture)
        XCTAssertFalse(PlatformCapabilities.supportsAlternateAppIcons)
        XCTAssertFalse(PlatformCapabilities.supportsLiveActivities)
        XCTAssertFalse(PlatformCapabilities.supportsIOSShareExtension)
        XCTAssertFalse(PlatformCapabilities.showsIOSActionButtonGuidance)
        XCTAssertFalse(PlatformCapabilities.supportsSlideToCancelVoiceNotes)
        #else
        XCTAssertFalse(PlatformCapabilities.isMacCatalyst)
        XCTAssertFalse(PlatformCapabilities.supportsDedicatedSettingsWindow)
        XCTAssertFalse(PlatformCapabilities.usesNativeSessionFileExporter)
        XCTAssertTrue(PlatformCapabilities.supportsHaptics)
        XCTAssertTrue(PlatformCapabilities.supportsCameraCapture)
        XCTAssertTrue(PlatformCapabilities.supportsAlternateAppIcons)
        XCTAssertTrue(PlatformCapabilities.supportsLiveActivities)
        XCTAssertTrue(PlatformCapabilities.supportsIOSShareExtension)
        XCTAssertTrue(PlatformCapabilities.showsIOSActionButtonGuidance)
        XCTAssertTrue(PlatformCapabilities.supportsSlideToCancelVoiceNotes)
        #endif
    }

    func testResponseNotificationPermissionLabelsUseTheRequestedPlatform() {
        XCTAssertEqual(
            ResponseNotificationPermissionLabel.text(for: .authorized, isMacCatalyst: true),
            "Mac notifications allowed."
        )
        XCTAssertEqual(
            ResponseNotificationPermissionLabel.text(for: .notDetermined, isMacCatalyst: true),
            "Mac permission not requested."
        )
        XCTAssertEqual(
            ResponseNotificationPermissionLabel.text(for: .denied, isMacCatalyst: true),
            "Mac notifications disabled."
        )

        XCTAssertEqual(
            ResponseNotificationPermissionLabel.text(for: .authorized, isMacCatalyst: false),
            "iOS notifications allowed."
        )
        XCTAssertEqual(
            ResponseNotificationPermissionLabel.text(for: .notDetermined, isMacCatalyst: false),
            "iOS permission not requested."
        )
        XCTAssertEqual(
            ResponseNotificationPermissionLabel.text(for: .denied, isMacCatalyst: false),
            "iOS notifications disabled."
        )
    }

    #if targetEnvironment(macCatalyst)
    @MainActor
    func testRuntimeCatalystIdiomMatchesProcessedDeviceFamily() throws {
        let families = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int])
        let expected: UIUserInterfaceIdiom = families.contains(6) ? .mac : .pad
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        XCTAssertEqual(UIDevice.current.userInterfaceIdiom, expected)
        XCTAssertEqual(scene.traitCollection.userInterfaceIdiom, expected)
        print("[PERF] CatalystIdiom deviceFamily=\(families) deviceIdiom=\(UIDevice.current.userInterfaceIdiom.rawValue) sceneIdiom=\(scene.traitCollection.userInterfaceIdiom.rawValue) screenScale=\(scene.screen.scale) displayScale=\(scene.traitCollection.displayScale) screenBounds=\(scene.screen.bounds) sceneBounds=\(scene.coordinateSpace.bounds) bodyFontPoints=\(UIFont.preferredFont(forTextStyle: .body).pointSize)")
    }

    @MainActor
    func testReviewSurfaceConstructsForCurrentCatalystIdiom() {
        let surface = ReviewDiffSurfaceView()
        surface.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        surface.layoutIfNeeded()
        XCTAssertEqual(surface.bounds.size, CGSize(width: 900, height: 600))
    }

    @MainActor
    func testMacWindowSizingRemovesStaleMaximumAcrossRepeatedLayouts() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let restrictions = try XCTUnwrap(scene.sizeRestrictions)
        let originalMinimum = restrictions.minimumSize
        let originalMaximum = restrictions.maximumSize
        let originalFullScreen = restrictions.allowsFullScreen
        defer {
            restrictions.minimumSize = originalMinimum
            restrictions.maximumSize = originalMaximum
            restrictions.allowsFullScreen = originalFullScreen
        }

        // Simulate an old/default cap, including one inherited from a smaller
        // display. Both scenes must clear it every time layout is reconciled.
        for maximum in [CGSize(width: 2_560, height: 1_440), CGSize(width: 5_120, height: 2_880)] {
            restrictions.maximumSize = maximum
            restrictions.allowsFullScreen = false
            for minimum in [MacWindowSizingPolicy.mainMinimumSize, MacWindowSizingPolicy.settingsMinimumSize] {
                MacWindowSizingPolicy.apply(to: restrictions, minimumSize: minimum)
                MacWindowSizingPolicy.apply(to: restrictions, minimumSize: minimum)
                XCTAssertEqual(restrictions.maximumSize, MacWindowSizingPolicy.unconstrainedMaximumSize)
                XCTAssertEqual(restrictions.minimumSize, minimum)
                XCTAssertTrue(restrictions.allowsFullScreen)
            }
        }
    }
    #endif
}
