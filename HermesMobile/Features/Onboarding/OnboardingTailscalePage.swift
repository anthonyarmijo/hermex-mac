import SwiftUI

struct OnboardingTailscalePage: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                OnboardingStepHeader(
                    stepNumber: 2,
                    icon: PlatformCapabilities.isMacCatalyst ? "desktopcomputer" : "iphone.and.arrow.forward",
                    title: OnboardingFlowPolicy.clientSpecificCopy(String(localized: "Install Tailscale on iPhone")),
                    description: OnboardingFlowPolicy.clientSpecificCopy(String(localized: "Install Tailscale on your iPhone and sign into the same tailnet as your server. Your agent will reply with the exact URL to use on the next screen."))
                )

                VStack(alignment: .leading, spacing: 14) {
                    tailscaleStep(
                        number: "1",
                        text: PlatformCapabilities.isMacCatalyst
                            ? OnboardingFlowPolicy.clientSpecificCopy(String(localized: "Install Tailscale on iPhone"))
                            : String(localized: "Install Tailscale from the App Store.")
                    )
                    tailscaleStep(number: "2", text: String(localized: "Sign in with the same account you used on your server."))
                    tailscaleStep(number: "3", text: String(localized: "Keep Tailscale connected while using Hermex."))

                    Button(action: openTailscaleInAppStore) {
                        Label(
                            PlatformCapabilities.isMacCatalyst
                                ? OnboardingFlowPolicy.clientSpecificCopy(String(localized: "Install Tailscale on iPhone"))
                                : String(localized: "Get Tailscale on the App Store"),
                            systemImage: "arrow.up.forward.square"
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.74, blue: 0.10))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        PlatformCapabilities.isMacCatalyst
                            ? ""
                            : String(localized: "Opens the Tailscale page in the App Store.")
                    )
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func openTailscaleInAppStore() {
        let primaryURL = OnboardingFlowPolicy.tailscaleClientDownloadURL()
        openURL(primaryURL, completion: { accepted in
            guard !accepted else { return }
            guard !PlatformCapabilities.isMacCatalyst else { return }
            openURL(OnboardingFlowPolicy.tailscaleAppStoreFallbackURL)
        })
    }

    private func tailscaleStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 23, height: 23)
                .background(Color(red: 1.0, green: 0.74, blue: 0.10), in: Circle())

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
