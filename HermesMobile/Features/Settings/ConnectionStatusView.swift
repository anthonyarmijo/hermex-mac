import SwiftUI
import UIKit

struct ConnectionStatusView: View {
    @Bindable var authManager: AuthManager
    @State private var model = ConnectionStatusModel()
    @Environment(\.dismiss) private var dismiss
    var onManageServers: (() -> Void)? = nil

    private var server: URL? { authManager.state.server }
    private var account: ServerAccount? { authManager.servers.first { $0.id == server?.absoluteString } }

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Name", value: account?.displayName ?? String(localized: "No server selected"))
                if server != nil {
                    Text(ConnectionURLDisplay.sanitized(server))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .accessibilityLabel("Server URL: \(ConnectionURLDisplay.sanitized(server))")
                    Button("Copy Server URL", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = ConnectionURLDisplay.sanitized(server)
                    }
                }
            }
            Section("Connection") {
                LabeledContent("Reachability", value: reachabilityLabel)
                LabeledContent("Authentication", value: authenticationLabel)
                if let milliseconds = model.latencyMilliseconds {
                    LabeledContent("Health response", value: String(format: "%.0f ms", milliseconds))
                }
                if let date = model.checkedAt {
                    LabeledContent("Last checked") { Text(date, format: .dateTime.hour().minute().second()) }
                }
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label(model.reachability == .checking ? "Checking…" : "Check Connection", systemImage: "arrow.clockwise")
                }
                .disabled(server == nil || model.reachability == .checking)
                .keyboardShortcut("r", modifiers: .command)
            }
            Section(model.versionsAreStale ? "Last Known Versions" : "Versions") {
                LabeledContent("Hermes WebUI", value: version(model.versions?.webUI))
                LabeledContent("Hermes Agent", value: version(model.versions?.agent))
                if model.versionsAreStale, let date = model.versionsCheckedAt {
                    Text("These versions were last verified \(date.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !model.diagnostics.isEmpty {
                Section("Details") {
                    ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, failure in
                        Text(failure.message)
                    }
                }
            }
            Section {
                if model.authentication == .required {
                    Button("Sign In") {
                        // This explicit action uses the existing expired-session
                        // flow and preserves the configured URL and custom headers.
                        authManager.handleAPIError(APIError.unauthorized)
                        dismiss()
                    }
                }
                if let account {
                    NavigationLink("Edit Server") {
                        ServerDetailView(authManager: authManager, account: account)
                    }
                } else if let onManageServers {
                    Button("Manage Servers") { dismiss(); onManageServers() }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hermex connects to Hermes WebUI. The server machine must be awake and reachable while you use the app.")
                    if ConnectionURLDisplay.isLoopback(server) {
                        Text("Localhost refers to this Mac. To connect from another Mac, use the server machine’s reachable network or private HTTPS address.")
                    }
                    Text("Reachability does not guarantee that every server feature is compatible. Checks run when this screen opens or when you refresh.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connection Status")
        .task(id: server) {
            model.select(server: server)
            await model.refresh()
        }
        .onDisappear { model.cancel() }
    }

    private func version(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return String(localized: "Unavailable") }
        return String(value.prefix(160))
    }

    private var reachabilityLabel: String {
        switch model.reachability {
        case .unconfigured: String(localized: "Not configured")
        case .notChecked: String(localized: "Not checked")
        case .checking: String(localized: "Checking…")
        case .reachable: String(localized: "Reachable")
        case .unreachable: String(localized: "Unreachable")
        }
    }

    private var authenticationLabel: String {
        switch model.authentication {
        case .unknown: String(localized: "Unknown")
        case .signedIn: String(localized: "Signed in")
        case .required: String(localized: "Sign-in required")
        case .notRequired: String(localized: "Not required by this server")
        }
    }
}
