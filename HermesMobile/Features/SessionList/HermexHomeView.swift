import SwiftUI

struct HermexHomeModel: Equatable {
    static let recentSessionLimit = 5

    let projects: [ProjectSummary]
    let recentSessions: [SessionSummary]
    private let sessions: [SessionSummary]

    init(sessions: [SessionSummary], projects: [ProjectSummary]) {
        let visibleSessions = sessions.filter {
            $0.archived != true && $0.shouldAppearInSessionList
        }
        self.sessions = visibleSessions
        self.projects = projects.filter { project in
            guard let projectID = project.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !projectID.isEmpty
        }
        recentSessions = Array(
            visibleSessions
                .sorted { Self.timestamp(for: $0) > Self.timestamp(for: $1) }
                .prefix(Self.recentSessionLimit)
        )
    }

    func sessionCount(for project: ProjectSummary) -> Int {
        guard let projectID = project.projectId else { return 0 }
        return sessions.filter { $0.projectId == projectID }.count
    }

    static func displayName(for project: ProjectSummary) -> String {
        let name = project.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else {
            return String(localized: "Untitled Project")
        }
        return name
    }

    static func chatCountTitle(_ count: Int) -> String {
        count == 1 ? String(localized: "1 chat") : String(localized: "\(count) chats")
    }

    private static func timestamp(for session: SessionSummary) -> Double {
        session.lastMessageAt ?? session.updatedAt ?? session.createdAt ?? 0
    }
}

struct HermexHomeView: View {
    let model: HermexHomeModel
    let logoColor: Color
    let isViewingCachedData: Bool
    let isStartingNewChat: Bool
    let showsMessageCount: Bool
    let showsWorkspace: Bool
    let onNewChat: () -> Void
    let onNewProjectChat: (ProjectSummary) -> Void
    let onOpenSession: (SessionSummary) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero

                if !model.projects.isEmpty {
                    projectsSection
                }

                recentChatsSection
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier("hermex-home")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            HermesHeaderLogo(selectedColor: logoColor)
                .frame(width: 230, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Ready when you are")
                    .font(.largeTitle.weight(.bold))

                Text("Start something new, continue recent work, or begin directly inside a project.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onNewChat) {
                Label("New Chat", systemImage: "square.and.pencil")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(creationIsDisabled)
            .help(isViewingCachedData ? "New chats require a connection" : "New Chat (⌘N)")
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 0.5)
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Start in a Project", systemImage: "folder")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(model.projects) { project in
                    projectButton(project)
                }
            }
        }
    }

    private func projectButton(_ project: ProjectSummary) -> some View {
        let name = HermexHomeModel.displayName(for: project)
        let count = model.sessionCount(for: project)

        return Button {
            onNewProjectChat(project)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(projectColor(project))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(HermexHomeModel.chatCountTitle(count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(creationIsDisabled)
        .help(isViewingCachedData ? "New chats require a connection" : "New Chat in \(name)")
        .accessibilityLabel(String(localized: "New Chat in \(name)"))
        .accessibilityValue(HermexHomeModel.chatCountTitle(count))
    }

    private var recentChatsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Recent Chats", systemImage: "clock")

            if model.recentSessions.isEmpty {
                Text("Your recent chats will appear here.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.recentSessions) { session in
                        Button {
                            onOpenSession(session)
                        } label: {
                            SessionRowView(
                                session: session,
                                showsMessageCount: showsMessageCount,
                                showsWorkspace: showsWorkspace,
                                isViewingCachedData: isViewingCachedData
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title2.weight(.semibold))
    }

    private var creationIsDisabled: Bool {
        isViewingCachedData || isStartingNewChat
    }

    private func projectColor(_ project: ProjectSummary) -> Color {
        if let color = Color(hexString: project.color) {
            return color
        }

        let source = project.projectId ?? HermexHomeModel.displayName(for: project)
        switch source.unicodeScalars.reduce(0, { $0 &+ Int($1.value) }) % 5 {
        case 0: return .green
        case 1: return .blue
        case 2: return .red
        case 3: return .orange
        default: return .accentColor
        }
    }
}
