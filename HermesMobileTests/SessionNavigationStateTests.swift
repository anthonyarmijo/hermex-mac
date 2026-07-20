import XCTest
@testable import HermesMobile

final class SessionNavigationStateTests: XCTestCase {
    func testSelectingSessionUpdatesDestinationAndRestorationID() {
        let session = SessionSummary(sessionId: "session-1", title: "One")
        var state = SessionNavigationState()

        state.select(session)

        XCTAssertEqual(state.destination, .session(session))
        XCTAssertEqual(state.selectedSessionID, "session-1")
        XCTAssertEqual(state.lastSelectedSessionID, "session-1")
    }

    func testRestoreSelectsStoredSessionWhenItStillExists() {
        let first = SessionSummary(sessionId: "session-1", title: "One")
        let second = SessionSummary(sessionId: "session-2", title: "Two")
        var state = SessionNavigationState(lastSelectedSessionID: "session-2")

        state.restoreIfNeeded(from: [first, second])

        XCTAssertEqual(state.destination, .session(second))
        XCTAssertEqual(state.lastSelectedSessionID, "session-2")
    }

    func testRestoreClearsStoredSelectionWhenSessionNoLongerExists() {
        var state = SessionNavigationState(lastSelectedSessionID: "missing")

        state.restoreIfNeeded(from: [SessionSummary(sessionId: "session-1")])

        XCTAssertNil(state.destination)
        XCTAssertNil(state.lastSelectedSessionID)
    }

    func testRestorePreservesStoredSelectionWhenSessionListIsNotAuthoritative() {
        var state = SessionNavigationState(lastSelectedSessionID: "session-1")

        state.restoreIfNeeded(from: [], clearsMissingSelection: false)

        XCTAssertNil(state.destination)
        XCTAssertEqual(state.lastSelectedSessionID, "session-1")
    }

    func testExplicitNewChatRouteOverridesStoredSelection() {
        let route = PendingNewChatRoute(initialDraft: "Shared draft")
        var state = SessionNavigationState(lastSelectedSessionID: "session-1")
        state.select(route)

        state.restoreIfNeeded(from: [SessionSummary(sessionId: "session-1")])

        XCTAssertEqual(state.destination, .newChat(route))
        XCTAssertEqual(state.lastSelectedSessionID, "session-1")
    }

    func testHomePreservesRememberedSessionAndBlocksAutomaticRestore() {
        let remembered = SessionSummary(sessionId: "session-1", title: "One")
        var state = SessionNavigationState(lastSelectedSessionID: "session-1")

        state.selectHome()
        state.restoreIfNeeded(from: [remembered])

        XCTAssertEqual(state.destination, .home)
        XCTAssertNil(state.selectedSessionID)
        XCTAssertEqual(state.lastSelectedSessionID, "session-1")
    }

    func testProjectNewChatRouteCarriesProjectMetadata() {
        let route = PendingNewChatRoute(projectID: "project-1", projectName: "Hermex")

        XCTAssertEqual(route.projectID, "project-1")
        XCTAssertEqual(route.projectName, "Hermex")
    }

    func testHomeModelLimitsAndSortsRecentChatsAndCountsProjects() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let project = try decoder.decode(
            ProjectSummary.self,
            from: Data(#"{"project_id":"project-1","name":"Hermex"}"#.utf8)
        )
        let sessions = (1...7).map { index in
            SessionSummary(
                sessionId: "session-\(index)",
                title: "Chat \(index)",
                messageCount: 1,
                lastMessageAt: Double(index),
                archived: index == 7,
                projectId: index <= 3 ? "project-1" : nil
            )
        }

        let model = HermexHomeModel(sessions: sessions, projects: [project])

        XCTAssertEqual(model.recentSessions.map(\.sessionId), ["session-6", "session-5", "session-4", "session-3", "session-2"])
        XCTAssertEqual(model.sessionCount(for: project), 3)
        XCTAssertEqual(model.projects, [project])
        XCTAssertEqual(HermexHomeModel.chatCountTitle(1), "1 chat")
        XCTAssertEqual(HermexHomeModel.chatCountTitle(3), "3 chats")
    }

    func testExplicitSessionRouteOverridesStoredSelection() {
        let stored = SessionSummary(sessionId: "stored")
        let deepLinked = SessionSummary(sessionId: "deep-linked")
        var state = SessionNavigationState(lastSelectedSessionID: "stored")
        state.select(deepLinked)

        state.restoreIfNeeded(from: [stored])

        XCTAssertEqual(state.destination, .session(deepLinked))
        XCTAssertEqual(state.lastSelectedSessionID, "deep-linked")
    }

    func testCreatedSessionRemainsSelectedWhileNewChatRouteOwnsItsDraft() {
        let route = PendingNewChatRoute(initialDraft: "Shared draft")
        let created = SessionSummary(sessionId: "created-session")
        var state = SessionNavigationState()
        state.select(route)
        XCTAssertTrue(state.isCreatingNewChat)

        state.remember(created)

        XCTAssertEqual(state.destination, .newChat(route))
        XCTAssertEqual(state.selectedSessionID, "created-session")
        XCTAssertEqual(state.lastSelectedSessionID, "created-session")
        XCTAssertFalse(state.isCreatingNewChat)
    }

    func testSelectingAnotherNewChatRouteStartsFreshCreationState() {
        let firstRoute = PendingNewChatRoute()
        let secondRoute = PendingNewChatRoute()
        var state = SessionNavigationState()
        state.select(firstRoute)
        state.remember(SessionSummary(sessionId: "created-session"))

        state.select(secondRoute)

        XCTAssertEqual(state.destination, .newChat(secondRoute))
        XCTAssertNil(state.selectedSessionID)
        XCTAssertTrue(state.isCreatingNewChat)
    }

    func testRemovingSelectedSessionClearsDestinationAndRestorationID() {
        let session = SessionSummary(sessionId: "session-1")
        var state = SessionNavigationState()
        state.select(session)

        state.remove(sessionID: "session-1")

        XCTAssertNil(state.destination)
        XCTAssertNil(state.lastSelectedSessionID)
    }

    func testRemovingRememberedSessionPreservesDifferentVisibleDestination() {
        var state = SessionNavigationState(lastSelectedSessionID: "session-1")
        state.select(SessionListUtilityDestination.tasks)

        state.remove(sessionID: "session-1")

        XCTAssertEqual(state.destination, .utility(.tasks))
        XCTAssertNil(state.lastSelectedSessionID)
    }

    func testUtilityDestinationRemainsSelectedAcrossLayoutReevaluation() {
        var state = SessionNavigationState()
        state.select(SessionListUtilityDestination.settings(nil))

        let reevaluatedState = state

        XCTAssertEqual(reevaluatedState.destination, .utility(.settings(nil)))
        XCTAssertNil(reevaluatedState.selectedSessionID)
    }

    func testReselectingRootDestinationAdvancesNavigationRevision() {
        var state = SessionNavigationState()
        state.select(SessionListUtilityDestination.skills)
        let firstRevision = state.rootRevision

        state.select(SessionListUtilityDestination.skills)

        XCTAssertEqual(state.destination, .utility(.skills))
        XCTAssertGreaterThan(state.rootRevision, firstRevision)
    }

    func testReadableContentWidthsKeepSecondaryAndWorkspaceSurfacesDistinct() {
        XCTAssertEqual(AdaptiveReadableContentWidth.secondaryDestination, 800)
        XCTAssertEqual(AdaptiveReadableContentWidth.workspace, 1_000)
        XCTAssertLessThan(
            AdaptiveReadableContentWidth.secondaryDestination,
            AdaptiveReadableContentWidth.workspace
        )
    }

    func testPersistenceUsesIndependentKeysPerServer() throws {
        let suiteName = "SessionNavigationStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstServer = try XCTUnwrap(URL(string: "https://first.example.com"))
        let secondServer = try XCTUnwrap(URL(string: "https://second.example.com"))

        SessionNavigationPersistence.save("first-session", for: firstServer, defaults: defaults)
        SessionNavigationPersistence.save("second-session", for: secondServer, defaults: defaults)

        XCTAssertEqual(
            SessionNavigationPersistence.load(for: firstServer, defaults: defaults),
            "first-session"
        )
        XCTAssertEqual(
            SessionNavigationPersistence.load(for: secondServer, defaults: defaults),
            "second-session"
        )
    }
}

final class SessionDraftPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SessionDraftPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDraftRoundTripsExactlyAcrossDefaultsReload() throws {
        let server = try XCTUnwrap(URL(string: "https://first.example.com"))
        let draft = "  First line\n\nSecond line with trailing space  "

        SessionDraftPersistence.save(draft, for: " session-1 ", server: server, defaults: defaults)

        let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(
            SessionDraftPersistence.load(for: "session-1", server: server, defaults: reloadedDefaults),
            draft
        )
    }

    func testEmptyDraftRemovesPersistedValue() throws {
        let server = try XCTUnwrap(URL(string: "https://first.example.com"))
        SessionDraftPersistence.save("Keep this", for: "session-1", server: server, defaults: defaults)

        SessionDraftPersistence.save("", for: "session-1", server: server, defaults: defaults)

        XCTAssertNil(SessionDraftPersistence.load(for: "session-1", server: server, defaults: defaults))
    }

    func testDraftsAreIsolatedByServerAndSession() throws {
        let firstServer = try XCTUnwrap(URL(string: "https://first.example.com"))
        let secondServer = try XCTUnwrap(URL(string: "https://second.example.com"))

        SessionDraftPersistence.save("First", for: "session-1", server: firstServer, defaults: defaults)
        SessionDraftPersistence.save("Second", for: "session-2", server: firstServer, defaults: defaults)
        SessionDraftPersistence.save("Other server", for: "session-1", server: secondServer, defaults: defaults)

        XCTAssertEqual(SessionDraftPersistence.load(for: "session-1", server: firstServer, defaults: defaults), "First")
        XCTAssertEqual(SessionDraftPersistence.load(for: "session-2", server: firstServer, defaults: defaults), "Second")
        XCTAssertEqual(
            SessionDraftPersistence.load(for: "session-1", server: secondServer, defaults: defaults),
            "Other server"
        )
    }

    func testRemovingServerDraftsDoesNotTouchAnotherServer() throws {
        let removedServer = try XCTUnwrap(URL(string: "https://removed.example.com"))
        let retainedServer = try XCTUnwrap(URL(string: "https://retained.example.com"))
        SessionDraftPersistence.save("Remove", for: "session-1", server: removedServer, defaults: defaults)
        SessionDraftPersistence.save("Retain", for: "session-1", server: retainedServer, defaults: defaults)

        SessionDraftPersistence.removeAll(for: removedServer, defaults: defaults)

        XCTAssertNil(SessionDraftPersistence.load(for: "session-1", server: removedServer, defaults: defaults))
        XCTAssertEqual(
            SessionDraftPersistence.load(for: "session-1", server: retainedServer, defaults: defaults),
            "Retain"
        )
    }
}
