import SwiftUI
import SwiftData

struct HermexSceneActions {
    let canCreateNewChat: Bool
    let createNewChat: () -> Void
    let searchSessions: () -> Void
}

enum HermexSceneID {
    static let settings = "settings"
    static let settingsValue = "singleton"
}

@MainActor
@Observable
final class HermexSettingsWindowModel {
    static let shared = HermexSettingsWindowModel()

    private(set) var initialScrollTarget: SettingsScrollAnchor?
    private(set) var requestID = 0

    private init() {}

    func request(scrollTo target: SettingsScrollAnchor? = nil) {
        initialScrollTarget = target
        requestID &+= 1
    }
}

private struct HermexSceneActionsKey: FocusedValueKey {
    typealias Value = HermexSceneActions
}

extension FocusedValues {
    var hermexSceneActions: HermexSceneActions? {
        get { self[HermexSceneActionsKey.self] }
        set { self[HermexSceneActionsKey.self] = newValue }
    }
}

struct HermexCommands: Commands {
    @FocusedValue(\.hermexSceneActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                actions?.createNewChat()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(actions?.canCreateNewChat != true)
        }

        CommandGroup(after: .newItem) {
            Button("Search Sessions") {
                actions?.searchSessions()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions == nil)
        }

        #if targetEnvironment(macCatalyst)
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                HermexSettingsWindowModel.shared.request()
                openWindow(id: HermexSceneID.settings, value: HermexSceneID.settingsValue)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct MacSettingsWindowRoot: View {
    @Bindable var authManager: AuthManager
    @AppStorage(AppTheme.storageKey) private var appThemeRawValue = AppTheme.system.rawValue
    @State private var windowModel = HermexSettingsWindowModel.shared

    var body: some View {
        NavigationStack {
            switch authManager.state {
            case .loggedIn(let server):
                SettingsView(
                    authManager: authManager,
                    server: server,
                    initialScrollTarget: windowModel.initialScrollTarget
                )
                .id("\(server.absoluteString)#\(windowModel.requestID)")
            case .loggedOut:
                ContentUnavailableView {
                    Label("Sign In Required", systemImage: "lock")
                } description: {
                    Text("Sign in from the main Hermex window to manage this server.")
                }
            case .unconfigured:
                ContentUnavailableView {
                    Label("Connect a Server", systemImage: "network")
                } description: {
                    Text("Connect Hermex to a server in the main window before changing settings.")
                }
            }
        }
        .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
        .frame(
            minWidth: MacWindowSizingPolicy.settingsMinimumSize.width,
            idealWidth: 720,
            minHeight: MacWindowSizingPolicy.settingsMinimumSize.height,
            idealHeight: 760
        )
        .background(MacWindowTitle(title: "Settings"))
        .background(
            MacWindowSizeRestrictions(
                minimumSize: MacWindowSizingPolicy.settingsMinimumSize
            )
        )
    }
}

enum MacWindowSizingPolicy {
    static let mainMinimumSize = CGSize(width: 900, height: 600)
    static let settingsMinimumSize = CGSize(width: 620, height: 560)

    static func maximumSize(for screenSize: CGSize, minimumSize: CGSize) -> CGSize {
        CGSize(
            width: max(screenSize.width, minimumSize.width),
            height: max(screenSize.height, minimumSize.height)
        )
    }
}

private struct MacWindowSizeRestrictions: UIViewRepresentable {
    let minimumSize: CGSize

    func makeUIView(context: Context) -> WindowSizeRestrictionsView {
        WindowSizeRestrictionsView(minimumSize: minimumSize)
    }

    func updateUIView(_ view: WindowSizeRestrictionsView, context: Context) {
        view.minimumSize = minimumSize
        view.applyRestrictions()
    }

    final class WindowSizeRestrictionsView: UIView {
        var minimumSize: CGSize

        init(minimumSize: CGSize) {
            self.minimumSize = minimumSize
            super.init(frame: .zero)
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyRestrictions()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyRestrictions()
        }

        func applyRestrictions() {
            guard let windowScene = window?.windowScene,
                  let restrictions = windowScene.sizeRestrictions else {
                return
            }

            let maximumSize = MacWindowSizingPolicy.maximumSize(
                for: windowScene.screen.bounds.size,
                minimumSize: minimumSize
            )

            if restrictions.minimumSize != minimumSize {
                restrictions.minimumSize = minimumSize
            }
            if restrictions.maximumSize != maximumSize {
                restrictions.maximumSize = maximumSize
            }
            if !restrictions.allowsFullScreen {
                restrictions.allowsFullScreen = true
            }
        }
    }
}

private struct MacWindowTitle: UIViewRepresentable {
    let title: String

    func makeUIView(context: Context) -> WindowTitleView {
        WindowTitleView(title: title)
    }

    func updateUIView(_ view: WindowTitleView, context: Context) {
        view.title = title
        view.applyTitle()
    }

    final class WindowTitleView: UIView {
        var title: String

        init(title: String) {
            self.title = title
            super.init(frame: .zero)
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyTitle()
        }

        func applyTitle() {
            window?.windowScene?.title = title
        }
    }
}
#endif

@main
struct HermesMobileApp: App {
    @State private var authManager = AuthManager()
    @AppStorage(AppTheme.storageKey) private var appThemeRawValue = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Launch argument hook so the Streaming Lab can be opened without
            // UI navigation (agent-driven simulator diagnosis, issue #234):
            // `xcrun simctl launch <udid> com.anthonyarmijo.hermex --streaming-lab`
            if ProcessInfo.processInfo.arguments.contains("--streaming-lab") {
                NavigationStack {
                    StreamingLabView()
                }
            } else {
                ContentView(authManager: authManager)
                    .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
                    #if targetEnvironment(macCatalyst)
                    .frame(
                        minWidth: MacWindowSizingPolicy.mainMinimumSize.width,
                        maxWidth: .infinity,
                        minHeight: MacWindowSizingPolicy.mainMinimumSize.height,
                        maxHeight: .infinity
                    )
                    .background(
                        MacWindowSizeRestrictions(
                            minimumSize: MacWindowSizingPolicy.mainMinimumSize
                        )
                    )
                    #endif
            }
            #else
            ContentView(authManager: authManager)
                .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
                #if targetEnvironment(macCatalyst)
                .frame(
                    minWidth: MacWindowSizingPolicy.mainMinimumSize.width,
                    maxWidth: .infinity,
                    minHeight: MacWindowSizingPolicy.mainMinimumSize.height,
                    maxHeight: .infinity
                )
                .background(
                    MacWindowSizeRestrictions(
                        minimumSize: MacWindowSizingPolicy.mainMinimumSize
                    )
                )
                #endif
            #endif
        }
        .modelContainer(for: [CachedSession.self, CachedMessage.self])
        .commands {
            HermexCommands()
            SidebarCommands()
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1_100, height: 760)
        .windowResizability(.contentMinSize)
        #endif

        #if targetEnvironment(macCatalyst)
        WindowGroup(
            "Settings",
            id: HermexSceneID.settings,
            for: String.self
        ) { _ in
            MacSettingsWindowRoot(authManager: authManager)
        }
        .modelContainer(for: [CachedSession.self, CachedMessage.self])
        .defaultSize(width: 720, height: 760)
        .windowResizability(.contentMinSize)
        #endif
    }
}
