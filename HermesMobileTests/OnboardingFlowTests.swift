import XCTest
@testable import HermesMobile

final class OnboardingFlowTests: XCTestCase {
    func testPrimaryButtonTitlesFollowPagerFlow() {
        XCTAssertEqual(OnboardingFlowPolicy.primaryButtonTitle(for: 0), "Get Started")
        XCTAssertEqual(OnboardingFlowPolicy.primaryButtonTitle(for: 1), "Set Up")
        XCTAssertEqual(OnboardingFlowPolicy.primaryButtonTitle(for: 2), "Continue")
        XCTAssertEqual(OnboardingFlowPolicy.primaryButtonTitle(for: 3), "Continue")
        XCTAssertEqual(OnboardingFlowPolicy.primaryButtonTitle(for: 4), "Connect")
    }

    func testCopyReminderOnlyAppliesToAgentPromptPageWithoutCopy() {
        XCTAssertTrue(
            OnboardingFlowPolicy.shouldShowCopyReminder(
                page: OnboardingFlowPolicy.agentPromptPageIndex,
                hasCopiedAgentPrompt: false
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldShowCopyReminder(
                page: OnboardingFlowPolicy.agentPromptPageIndex,
                hasCopiedAgentPrompt: true
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldShowCopyReminder(
                page: OnboardingFlowPolicy.agentPromptPageIndex,
                hasCopiedAgentPrompt: false,
                hasBypassedCopyReminder: true
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldShowCopyReminder(
                page: OnboardingFlowPolicy.connectPageIndex,
                hasCopiedAgentPrompt: false
            )
        )
    }

    func testForwardSwipeFromAgentPromptRequiresCopyOrBypass() {
        XCTAssertTrue(
            OnboardingFlowPolicy.shouldInterceptForwardNavigationFromAgentPrompt(
                from: OnboardingFlowPolicy.agentPromptPageIndex,
                to: 3,
                hasCopiedAgentPrompt: false
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldInterceptForwardNavigationFromAgentPrompt(
                from: OnboardingFlowPolicy.agentPromptPageIndex,
                to: 3,
                hasCopiedAgentPrompt: true
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldInterceptForwardNavigationFromAgentPrompt(
                from: OnboardingFlowPolicy.agentPromptPageIndex,
                to: 3,
                hasCopiedAgentPrompt: false,
                hasBypassedCopyReminder: true
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldInterceptForwardNavigationFromAgentPrompt(
                from: OnboardingFlowPolicy.agentPromptPageIndex,
                to: 1,
                hasCopiedAgentPrompt: false
            )
        )
    }

    func testConnectFocusClearsWhenLeavingConnectPage() {
        XCTAssertTrue(OnboardingFlowPolicy.shouldClearConnectFocusWhenLeavingPage(3))
        XCTAssertFalse(OnboardingFlowPolicy.shouldClearConnectFocusWhenLeavingPage(OnboardingFlowPolicy.connectPageIndex))
    }

    func testServerShortcutShowsBeforeConnectPageOnly() {
        XCTAssertTrue(OnboardingFlowPolicy.showsServerShortcut(for: 0))
        XCTAssertTrue(OnboardingFlowPolicy.showsServerShortcut(for: 3))
        XCTAssertFalse(OnboardingFlowPolicy.showsServerShortcut(for: OnboardingFlowPolicy.connectPageIndex))
    }

    func testAgentSetupPromptIncludesCurrentSafeTailscaleRequirements() {
        let iPhonePrompt = OnboardingFlowPolicy.agentSetupPrompt(isMacCatalyst: false)
        let macPrompt = OnboardingFlowPolicy.agentSetupPrompt(isMacCatalyst: true)

        for prompt in [iPhonePrompt, macPrompt] {
            XCTAssertTrue(prompt.contains("hermes-webui"))
            XCTAssertTrue(prompt.contains("onboarding-agent-checklist.md"))
            XCTAssertTrue(prompt.contains("python3 bootstrap.py"))
            XCTAssertTrue(prompt.contains("HERMES_WEBUI_PASSWORD"))
            XCTAssertTrue(prompt.contains("tailscale serve --bg 8787"))
            XCTAssertTrue(prompt.contains("curl http://127.0.0.1:8787/health"))
            XCTAssertTrue(prompt.contains("Do not include passwords or tokens in the reply."))
            XCTAssertTrue(prompt.contains("Do not use Cloudflare."))
            XCTAssertTrue(prompt.contains("Hermex"))
            XCTAssertFalse(prompt.contains("it's a Node.js web app"))
            XCTAssertFalse(prompt.contains("bind the server to 0.0.0.0"))
        }

        XCTAssertTrue(iPhonePrompt.contains("Hermex on my iPhone"))
        XCTAssertTrue(iPhonePrompt.contains("Tailscale + iPhone."))
        XCTAssertTrue(macPrompt.contains("Hermex on my Mac"))
        XCTAssertTrue(macPrompt.contains("Tailscale + Mac."))
        XCTAssertFalse(macPrompt.contains("my iPhone"))
    }

    func testClientSpecificCopyPreservesIPhoneAndAdaptsMac() {
        let copy = "Install Tailscale on iPhone"

        XCTAssertEqual(
            OnboardingFlowPolicy.clientSpecificCopy(copy, isMacCatalyst: false),
            copy
        )
        XCTAssertEqual(
            OnboardingFlowPolicy.clientSpecificCopy(copy, isMacCatalyst: true),
            "Install Tailscale on Mac"
        )
    }

    func testTailscaleDownloadURLMatchesClientPlatform() {
        XCTAssertEqual(
            OnboardingFlowPolicy.tailscaleClientDownloadURL(isMacCatalyst: false).absoluteString,
            "itms-apps://apps.apple.com/us/app/tailscale/id1470499037"
        )
        XCTAssertEqual(
            OnboardingFlowPolicy.tailscaleClientDownloadURL(isMacCatalyst: true).absoluteString,
            "https://tailscale.com/download/mac"
        )
    }

    func testTailscaleAppStoreURLUsesITMSDeepLink() {
        XCTAssertEqual(
            OnboardingFlowPolicy.tailscaleAppStoreURL.absoluteString,
            "itms-apps://apps.apple.com/us/app/tailscale/id1470499037"
        )
        XCTAssertEqual(
            OnboardingFlowPolicy.tailscaleAppStoreFallbackURL.absoluteString,
            "https://apps.apple.com/us/app/tailscale/id1470499037"
        )
    }

    func testConnectPageIndexIsFinalPagerPage() {
        XCTAssertEqual(OnboardingFlowPolicy.connectPageIndex, OnboardingFlowPolicy.pageCount - 1)
    }
}
