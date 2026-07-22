import Foundation

enum OnboardingFlowPolicy {
    static let pageCount = 5
    static let connectPageIndex = 4
    static let agentPromptPageIndex = 2

    static var agentSetupPrompt: String {
        agentSetupPrompt(isMacCatalyst: PlatformCapabilities.isMacCatalyst)
    }

    static func agentSetupPrompt(isMacCatalyst: Bool) -> String {
        let clientDevice = isMacCatalyst ? "Mac" : "iPhone"

        return """
Set up Hermes Web UI on this machine for access from Hermex on my \(clientDevice) via Tailscale.

Before making changes, read https://github.com/nesquena/hermes-webui/blob/main/docs/onboarding-agent-checklist.md and inspect this machine for an existing Hermes Agent or Hermes Web UI installation. Preserve existing configuration, credentials, sessions, memory, and other Hermes data.
Use the supported Python bootstrap flow from https://github.com/nesquena/hermes-webui: clone the repository if it is not already installed, then use python3 bootstrap.py and the Web UI's first-run wizard. Do not treat Hermes Web UI as a Node.js app.
Enable password authentication with HERMES_WEBUI_PASSWORD before making the Web UI reachable from another device. Ask me to choose and enter the password; do not print the password, auth keys, cookies, or other secrets in your final reply.
Install Tailscale on this machine using the documented method for its OS. Pause for me to authenticate this machine to my tailnet; do not ask me to paste an auth key or login token into chat.
Make the Web UI reachable over Tailscale while keeping it bound to 127.0.0.1:
- Prefer tailscale serve --bg 8787 so Tailscale provides a private HTTPS URL for the local Web UI.
- If Tailscale Serve is unavailable, explain the alternatives and get my approval before changing the bind address or exposing a new network listener. Never expose an unauthenticated Web UI.
Ask before installing an auto-start service, then configure one appropriate for this OS if I approve it.
Verify the local service with curl http://127.0.0.1:8787/health, verify the Tailscale URL from the tailnet, and confirm password authentication is active.
Reply with:
- The exact server URL I enter in Hermex
- What you installed or changed
- Any setup steps I still need to do on my \(clientDevice)
Do not include passwords or tokens in the reply.
Do not use Cloudflare. Optimize for Tailscale + \(clientDevice).
"""
    }

    static let tailscaleAppStoreURL = URL(string: "itms-apps://apps.apple.com/us/app/tailscale/id1470499037")!

    static let tailscaleAppStoreFallbackURL = URL(string: "https://apps.apple.com/us/app/tailscale/id1470499037")!

    static let tailscaleMacDownloadURL = URL(string: "https://tailscale.com/download/mac")!

    static func tailscaleClientDownloadURL(
        isMacCatalyst: Bool = PlatformCapabilities.isMacCatalyst
    ) -> URL {
        isMacCatalyst ? tailscaleMacDownloadURL : tailscaleAppStoreURL
    }

    /// The onboarding catalog deliberately keeps Apple's platform names literal
    /// across translations, allowing Catalyst to reuse upstream iPhone copy while
    /// changing only the client device name.
    static func clientSpecificCopy(
        _ iPhoneCopy: String,
        isMacCatalyst: Bool = PlatformCapabilities.isMacCatalyst
    ) -> String {
        guard isMacCatalyst else { return iPhoneCopy }
        return iPhoneCopy
            .replacingOccurrences(of: "iPhonie", with: "Macu")
            .replacingOccurrences(of: "iPhone", with: "Mac")
    }

    static func primaryButtonTitle(for page: Int) -> String {
        switch page {
        case 0:
            return String(localized: "Get Started")
        case 1:
            return String(localized: "Set Up")
        case connectPageIndex:
            return String(localized: "Connect")
        default:
            return String(localized: "Continue")
        }
    }

    static func shouldShowCopyReminder(
        page: Int,
        hasCopiedAgentPrompt: Bool,
        hasBypassedCopyReminder: Bool = false
    ) -> Bool {
        page == agentPromptPageIndex && !hasCopiedAgentPrompt && !hasBypassedCopyReminder
    }

    static func shouldInterceptForwardNavigationFromAgentPrompt(
        from oldPage: Int,
        to newPage: Int,
        hasCopiedAgentPrompt: Bool,
        hasBypassedCopyReminder: Bool = false
    ) -> Bool {
        oldPage == agentPromptPageIndex
            && newPage > oldPage
            && !hasCopiedAgentPrompt
            && !hasBypassedCopyReminder
    }

    static func shouldClearConnectFocusWhenLeavingPage(_ page: Int) -> Bool {
        page != connectPageIndex
    }

    static func showsServerShortcut(for page: Int) -> Bool {
        page < connectPageIndex
    }
}
