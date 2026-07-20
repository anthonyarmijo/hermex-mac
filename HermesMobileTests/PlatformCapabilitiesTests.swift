import XCTest
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
    func testMacWindowSizingPolicyUsesTheCurrentScreenAsItsMaximum() {
        XCTAssertEqual(
            MacWindowSizingPolicy.maximumSize(
                for: CGSize(width: 3_440, height: 1_440),
                minimumSize: MacWindowSizingPolicy.mainMinimumSize
            ),
            CGSize(width: 3_440, height: 1_440)
        )
    }

    func testMacWindowSizingPolicyNeverProducesAMaximumBelowTheMinimum() {
        XCTAssertEqual(
            MacWindowSizingPolicy.maximumSize(
                for: CGSize(width: 640, height: 480),
                minimumSize: MacWindowSizingPolicy.mainMinimumSize
            ),
            MacWindowSizingPolicy.mainMinimumSize
        )
    }
    #endif
}
