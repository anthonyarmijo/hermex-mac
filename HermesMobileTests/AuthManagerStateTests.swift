import XCTest
@testable import HermesMobile

@MainActor
final class AuthManagerStateTests: XCTestCase {
    private struct PreconditionFailure: Error {}

    private static let sessionExpiredMessage = "Your session expired. Sign in again."

    // Foundation supplies a separate in-memory jar for each ephemeral configuration.
    // Never clear the hosted app's shared cookie store during setup or teardown.
    private let cookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage!

    func testUnauthorizedWhileLoggedInKeepsServerAndMovesToLoggedOut() async throws {
        let keychain = InMemoryKeychainStore()
        let manager = try await makeLoggedInManager(keychain: keychain, serverURLString: "https://example.test")
        let server = try XCTUnwrap(URL(string: "https://example.test"))
        cookieStorage.setCookie(try makeSessionCookie(for: server))

        manager.handleAPIError(APIError.unauthorized)

        XCTAssertEqual(manager.state, .loggedOut(server: server))
        XCTAssertEqual(keychain.savedValues[.serverURL], server.absoluteString)
        XCTAssertEqual(cookieStorage.cookies?.isEmpty, true)
        XCTAssertEqual(manager.lastErrorMessage, Self.sessionExpiredMessage)
    }

    func testUnauthorizedWhileAlreadyLoggedOutStaysLoggedOutWithServer() async throws {
        let keychain = InMemoryKeychainStore()
        let manager = try await makeLoggedInManager(keychain: keychain, serverURLString: "https://example.test")
        let server = try XCTUnwrap(URL(string: "https://example.test"))

        manager.handleAPIError(APIError.unauthorized)
        manager.handleAPIError(APIError.unauthorized)

        XCTAssertEqual(manager.state, .loggedOut(server: server))
        XCTAssertEqual(keychain.savedValues[.serverURL], server.absoluteString)
    }

    func testUnauthorizedWhileUnconfiguredKeepsFullClearBehavior() throws {
        let keychain = InMemoryKeychainStore()
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: keychain,
            clientFactory: { _ in MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false)) },
            headerStore: CustomHeaderStore(),
            serverRegistry: ServerRegistry.inMemory()
        )
        cookieStorage.setCookie(try makeSessionCookie(for: XCTUnwrap(URL(string: "https://a.test"))))
        cookieStorage.setCookie(try makeSessionCookie(for: XCTUnwrap(URL(string: "https://b.test"))))

        manager.handleAPIError(APIError.unauthorized)

        XCTAssertEqual(manager.state, .unconfigured)
        XCTAssertNil(keychain.savedValues[.serverURL])
        XCTAssertEqual(manager.lastErrorMessage, Self.sessionExpiredMessage)
        XCTAssertTrue(cookieStorage.cookies?.isEmpty ?? true)
    }

    func testAuthCleanupLeavesSyntheticCookieOutsideInjectedStoreUntouched() async throws {
        // Touch only our uniquely named synthetic cookie. Never copy, enumerate,
        // restore or delete the owner's cookie jar as part of a test harness.
        let server = try XCTUnwrap(URL(string: "https://auth-isolation-\(UUID().uuidString.lowercased()).invalid"))
        let sentinel = try makeSessionCookie(for: server, value: "synthetic-sentinel")
        let shared = HTTPCookieStorage.shared
        shared.setCookie(sentinel)
        defer { shared.deleteCookie(sentinel) }
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: InMemoryKeychainStore(),
            clientFactory: { _ in MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: false)) },
            headerStore: CustomHeaderStore(),
            serverRegistry: ServerRegistry.inMemory()
        )

        // The unconfigured fallback clears the entire injected jar only.
        cookieStorage.setCookie(try makeSessionCookie(for: server, value: "test-session"))
        manager.handleAPIError(APIError.unauthorized)
        XCTAssertTrue(cookieStorage.cookies?.isEmpty ?? true)
        XCTAssertEqual(shared.cookies(for: server)?.map(\.value), ["synthetic-sentinel"])

        // Configured expiry and explicit logout preserve even a same-host cookie
        // outside that jar; domain/port scoping alone would not protect this.
        for signOut in [false, true] {
            await manager.configure(serverURLString: server.absoluteString, password: "")
            cookieStorage.setCookie(try makeSessionCookie(for: server, value: "test-session"))
            if signOut { await manager.signOut() }
            else { manager.handleAPIError(APIError.unauthorized) }
            XCTAssertTrue(cookieStorage.cookies?.isEmpty ?? true)
            XCTAssertEqual(shared.cookies(for: server)?.map(\.value), ["synthetic-sentinel"])
        }
    }

    func testNonUnauthorizedErrorDoesNotChangeState() async throws {
        let keychain = InMemoryKeychainStore()
        let manager = try await makeLoggedInManager(keychain: keychain, serverURLString: "https://example.test")
        let server = try XCTUnwrap(URL(string: "https://example.test"))

        manager.handleAPIError(APIError.http(statusCode: 502, body: ""))

        XCTAssertEqual(manager.state, .loggedIn(server: server))
        XCTAssertEqual(keychain.savedValues[.serverURL], server.absoluteString)
    }

    func testSignOutFullyClearsServerAndReturnsToUnconfigured() async throws {
        let keychain = InMemoryKeychainStore()
        let client = MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false))
        let manager = try await makeLoggedInManager(
            keychain: keychain,
            serverURLString: "https://example.test",
            client: client
        )

        await manager.signOut()

        XCTAssertEqual(manager.state, .unconfigured)
        XCTAssertNil(keychain.savedValues[.serverURL])
        // Server-side logout is still attempted best-effort when reachable.
        XCTAssertEqual(client.logoutCallCount, 1)
    }

    func testSignOutClearsLocalAuthWhenServerLogoutFails() async throws {
        let keychain = InMemoryKeychainStore()
        // Server unreachable: the best-effort logout throws, but local sign-out
        // must still succeed so the user can reach onboarding (issue #249).
        let client = MockAuthAPIClient(
            authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false),
            logoutBehavior: .fail(APIError.network(underlying: URLError(.notConnectedToInternet)))
        )
        let manager = try await makeLoggedInManager(
            keychain: keychain,
            serverURLString: "https://example.test",
            client: client
        )

        await manager.signOut()

        XCTAssertEqual(manager.state, .unconfigured)
        XCTAssertNil(keychain.savedValues[.serverURL])
        XCTAssertEqual(client.logoutCallCount, 1)
    }

    func testSignOutCompletesWhenServerLogoutHangs() async throws {
        let keychain = InMemoryKeychainStore()
        // Server accepts the connection but never responds: sign-out must still
        // finish once the bounded logout times out, not hang indefinitely.
        let client = MockAuthAPIClient(
            authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false),
            logoutBehavior: .hang
        )
        let manager = try await makeLoggedInManager(
            keychain: keychain,
            serverURLString: "https://example.test",
            client: client,
            logoutTimeout: .milliseconds(50)
        )

        await manager.signOut()

        XCTAssertEqual(manager.state, .unconfigured)
        XCTAssertNil(keychain.savedValues[.serverURL])
        XCTAssertEqual(client.logoutCallCount, 1)
    }

    func testSignOutClearsSessionCookies() async throws {
        let keychain = InMemoryKeychainStore()
        let server = try XCTUnwrap(URL(string: "https://example.test"))
        let client = MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false))
        let manager = try await makeLoggedInManager(
            keychain: keychain,
            serverURLString: "https://example.test",
            client: client
        )
        cookieStorage.setCookie(try makeSessionCookie(for: server))

        await manager.signOut()

        XCTAssertEqual(cookieStorage.cookies?.isEmpty, true)
        XCTAssertEqual(manager.state, .unconfigured)
    }

    // MARK: - Per-server isolation (#16)

    func testSignOutClearsOnlyActiveServerCookies() async throws {
        let keychain = InMemoryKeychainStore()
        let serverA = try XCTUnwrap(URL(string: "https://a.test"))
        let serverB = try XCTUnwrap(URL(string: "https://b.test"))
        let manager = try await makeLoggedInManager(keychain: keychain, serverURLString: "https://a.test")
        // Both servers hold a session cookie in the injected test jar.
        cookieStorage.setCookie(try makeSessionCookie(for: serverA, value: "a-cookie"))
        cookieStorage.setCookie(try makeSessionCookie(for: serverB, value: "b-cookie"))

        await manager.signOut()

        // A's cookie is cleared; B (a different host) is untouched.
        XCTAssertTrue(cookieStorage.cookies(for: serverA)?.isEmpty ?? true)
        XCTAssertEqual(cookieStorage.cookies(for: serverB)?.map(\.value), ["b-cookie"])
    }

    func testUnauthorizedClearsOnlyActiveServerCookies() async throws {
        let keychain = InMemoryKeychainStore()
        let serverA = try XCTUnwrap(URL(string: "https://a.test"))
        let serverB = try XCTUnwrap(URL(string: "https://b.test"))
        let manager = try await makeLoggedInManager(keychain: keychain, serverURLString: "https://a.test")
        cookieStorage.setCookie(try makeSessionCookie(for: serverA, value: "a-cookie"))
        cookieStorage.setCookie(try makeSessionCookie(for: serverB, value: "b-cookie"))

        manager.handleAPIError(APIError.unauthorized)

        // Only the active server's auth is affected by its 401.
        XCTAssertEqual(manager.state, .loggedOut(server: serverA))
        XCTAssertTrue(cookieStorage.cookies(for: serverA)?.isEmpty ?? true)
        XCTAssertEqual(cookieStorage.cookies(for: serverB)?.map(\.value), ["b-cookie"])
    }

    func testSignOutLeavesOtherServerHeadersAndRegistryIntact() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory()
        // Pre-seed server B: a registry entry plus its scoped custom headers.
        let serverB = try XCTUnwrap(URL(string: "https://b.test"))
        registry.activate(url: serverB)
        let bHeaders = try XCTUnwrap([CustomHeader(name: "X-B", value: "b-token")].encodedForStorage())
        try keychain.save(bHeaders, forKey: .customHeaders, scope: "https://b.test")

        // Sign in to server A as the active server, with its own scoped headers.
        let client = MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: false))
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: keychain,
            clientFactory: { _ in client },
            headerStore: CustomHeaderStore(),
            serverRegistry: registry
        )
        await manager.configure(
            serverURLString: "https://a.test",
            password: "",
            customHeaders: [CustomHeader(name: "X-A", value: "a-token")]
        )
        XCTAssertNotNil(keychain.scopedValue(.customHeaders, scope: "https://a.test"))

        await manager.signOut()

        // A's scoped headers + registry entry are gone; B's are untouched.
        XCTAssertNil(keychain.scopedValue(.customHeaders, scope: "https://a.test"))
        XCTAssertNotNil(keychain.scopedValue(.customHeaders, scope: "https://b.test"))
        XCTAssertEqual(registry.servers.map(\.id), ["https://b.test"])
    }

    // MARK: - Multi-server switch / remove / identity (#17)

    func testSwitchActiveServerMakesItActiveAndOptimisticallyLoggedIn() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let (manager, _, bAccount) = try await makeTwoServerManager(keychain: keychain, registry: registry)
        let serverB = try XCTUnwrap(URL(string: "https://b.test"))

        manager.switchActiveServer(to: bAccount)

        XCTAssertEqual(manager.state, .loggedIn(server: serverB))
        XCTAssertEqual(keychain.savedValues[.serverURL], "https://b.test")
        XCTAssertEqual(registry.activeServerID, "https://b.test")
        XCTAssertEqual(manager.activeServerID, "https://b.test")
    }

    func testSwitchToTheAlreadyActiveServerIsANoOp() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let (manager, aAccount, _) = try await makeTwoServerManager(keychain: keychain, registry: registry)
        let serverA = try XCTUnwrap(URL(string: "https://a.test"))

        manager.switchActiveServer(to: aAccount)

        XCTAssertEqual(manager.state, .loggedIn(server: serverA))
        XCTAssertEqual(registry.activeServerID, "https://a.test")
    }

    func testRemoveActiveServerAutoSwitchesToRemaining() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let (manager, aAccount, _) = try await makeTwoServerManager(keychain: keychain, registry: registry)
        let serverB = try XCTUnwrap(URL(string: "https://b.test"))

        await manager.removeServer(aAccount)

        XCTAssertEqual(manager.state, .loggedIn(server: serverB))
        XCTAssertEqual(registry.servers.map(\.id), ["https://b.test"])
        XCTAssertEqual(keychain.savedValues[.serverURL], "https://b.test")
    }

    func testRemoveLastServerReturnsToOnboarding() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: keychain,
            clientFactory: { _ in MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: false)) },
            serverRegistry: registry
        )
        await manager.configure(serverURLString: "https://a.test", password: "")
        let aAccount = try XCTUnwrap(registry.servers.first { $0.id == "https://a.test" })

        await manager.removeServer(aAccount)

        XCTAssertEqual(manager.state, .unconfigured)
        XCTAssertTrue(registry.servers.isEmpty)
        XCTAssertNil(keychain.savedValues[.serverURL])
    }

    func testRemoveNonActiveServerLeavesActiveLoggedIn() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let (manager, _, bAccount) = try await makeTwoServerManager(keychain: keychain, registry: registry)
        let serverA = try XCTUnwrap(URL(string: "https://a.test"))

        await manager.removeServer(bAccount)

        XCTAssertEqual(manager.state, .loggedIn(server: serverA))
        XCTAssertEqual(registry.servers.map(\.id), ["https://a.test"])
        XCTAssertEqual(keychain.savedValues[.serverURL], "https://a.test")
    }

    func testRemoveNonActiveServerClearsOnlyItsCookies() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let (manager, _, bAccount) = try await makeTwoServerManager(keychain: keychain, registry: registry)
        let serverA = try XCTUnwrap(URL(string: "https://a.test"))
        let serverB = try XCTUnwrap(URL(string: "https://b.test"))
        cookieStorage.setCookie(try makeSessionCookie(for: serverA, value: "a-cookie"))
        cookieStorage.setCookie(try makeSessionCookie(for: serverB, value: "b-cookie"))

        await manager.removeServer(bAccount)

        XCTAssertEqual(cookieStorage.cookies(for: serverA)?.map(\.value), ["a-cookie"])
        XCTAssertTrue(cookieStorage.cookies(for: serverB)?.isEmpty ?? true)
    }

    func testSignOutWithRemainingServerAutoSwitches() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let (manager, _, _) = try await makeTwoServerManager(keychain: keychain, registry: registry)
        let serverB = try XCTUnwrap(URL(string: "https://b.test"))

        await manager.signOut()

        XCTAssertEqual(manager.state, .loggedIn(server: serverB))
        XCTAssertEqual(registry.servers.map(\.id), ["https://b.test"])
    }

    func testConfiguringASecondServerAddsItAndMakesItActive() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: keychain,
            clientFactory: { _ in MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: false)) },
            serverRegistry: registry
        )

        await manager.configure(serverURLString: "https://a.test", password: "")
        await manager.configure(serverURLString: "https://b.test", password: "")

        XCTAssertEqual(Set(manager.servers.map(\.id)), ["https://a.test", "https://b.test"])
        XCTAssertEqual(manager.activeServerID, "https://b.test")
        XCTAssertEqual(manager.state, .loggedIn(server: try XCTUnwrap(URL(string: "https://b.test"))))
    }

    func testAddServerNeedsPasswordWhenAuthEnabledAndNoPassword() async {
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: InMemoryKeychainStore(),
            probeClientFactory: { _, _ in MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false)) },
            serverRegistry: ServerRegistry.inMemory()
        )

        let outcome = await manager.addServer(serverURLString: "https://needs-pw.test", password: "")

        XCTAssertEqual(outcome, .needsPassword)
        XCTAssertEqual(manager.state, .unconfigured)
        XCTAssertTrue(manager.servers.isEmpty)
    }

    func testAddServerRejectsAnAlreadyConfiguredURL() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: keychain,
            clientFactory: { _ in MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: false)) },
            serverRegistry: registry
        )
        await manager.configure(serverURLString: "https://a.test", password: "")

        let outcome = await manager.addServer(serverURLString: "https://a.test", password: "")

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(manager.lastErrorMessage, "This server is already configured.")
        XCTAssertEqual(manager.servers.map(\.id), ["https://a.test"])
        XCTAssertEqual(manager.state, .loggedIn(server: try XCTUnwrap(URL(string: "https://a.test"))))
    }

    func testAddServerSucceedsAndSwitchesActive() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: keychain,
            clientFactory: { _ in MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: false)) },
            probeClientFactory: { _, _ in MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: false)) },
            serverRegistry: registry
        )
        await manager.configure(serverURLString: "https://a.test", password: "")

        let outcome = await manager.addServer(serverURLString: "https://b.test", password: "")

        XCTAssertEqual(outcome, .added(try XCTUnwrap(URL(string: "https://b.test"))))
        XCTAssertEqual(manager.state, .loggedIn(server: try XCTUnwrap(URL(string: "https://b.test"))))
        XCTAssertEqual(Set(manager.servers.map(\.id)), ["https://a.test", "https://b.test"])
        XCTAssertEqual(keychain.savedValues[.serverURL], "https://b.test")
    }

    func testAddServerFailureKeepsActiveServerAndItsHeaders() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let clientA = MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false))
        let clientB = MockAuthAPIClient(
            authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false),
            loginResponse: LoginResponse(ok: false, message: nil, error: "nope")
        )
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: keychain,
            clientFactory: { $0.absoluteString.contains("a.test") ? clientA : clientB },
            probeClientFactory: { url, _ in url.absoluteString.contains("a.test") ? clientA : clientB },
            headerStore: CustomHeaderStore(),
            serverRegistry: registry
        )
        await manager.configure(
            serverURLString: "https://a.test",
            password: "secret",
            customHeaders: [CustomHeader(name: "X-A", value: "a-token")]
        )
        XCTAssertEqual(manager.state, .loggedIn(server: try XCTUnwrap(URL(string: "https://a.test"))))

        let outcome = await manager.addServer(
            serverURLString: "https://b.test",
            password: "wrong",
            customHeaders: [CustomHeader(name: "X-B", value: "b-token")]
        )

        XCTAssertEqual(outcome, .failed)
        // The active server, its state, registry, and live headers are untouched.
        XCTAssertEqual(manager.state, .loggedIn(server: try XCTUnwrap(URL(string: "https://a.test"))))
        XCTAssertEqual(manager.servers.map(\.id), ["https://a.test"])
        XCTAssertEqual(manager.currentCustomHeaders.map(\.name), ["X-A"])
        XCTAssertEqual(manager.currentCustomHeaders.map(\.value), ["a-token"])
    }

    func testServersSnapshotMirrorsRegistry() async throws {
        let keychain = InMemoryKeychainStore()
        let registry = ServerRegistry.inMemory(keychain: keychain)
        let (manager, _, _) = try await makeTwoServerManager(keychain: keychain, registry: registry)

        XCTAssertEqual(Set(manager.servers.map(\.id)), ["https://a.test", "https://b.test"])
        XCTAssertEqual(manager.activeServerID, "https://a.test")
    }

    func testUpdateServerIdentityPersistsAndMirrorsTheActiveServer() async throws {
        let keychain = InMemoryKeychainStore()
        let defaults = UserDefaults.ephemeral()
        let registry = ServerRegistry(keychain: keychain, identityDefaults: defaults)
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: keychain,
            clientFactory: { _ in MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: false)) },
            serverRegistry: registry
        )
        await manager.configure(serverURLString: "https://a.test", password: "")
        let aAccount = try XCTUnwrap(registry.servers.first { $0.id == "https://a.test" })

        manager.updateServerIdentity(
            aAccount,
            displayName: "Work",
            initials: "WK",
            headerLogoColorHex: "#5B7CFF"
        )

        let updated = try XCTUnwrap(manager.servers.first { $0.id == "https://a.test" })
        XCTAssertEqual(updated.displayName, "Work")
        XCTAssertEqual(updated.initials, "WK")
        XCTAssertEqual(updated.headerLogoColorHex, "#5B7CFF")
        // The active server's identity is mirrored into the global defaults.
        XCTAssertEqual(defaults.string(forKey: SessionIdentitySettings.displayNameKey), "Work")
        XCTAssertEqual(defaults.string(forKey: HeaderLogoColor.storageKey), "#5B7CFF")
    }

    /// Builds a manager with two registered servers: `a.test` signed in + active,
    /// `b.test` present but inactive. Returns the manager and both accounts.
    private func makeTwoServerManager(
        keychain: InMemoryKeychainStore,
        registry: ServerRegistry
    ) async throws -> (AuthManager, ServerAccount, ServerAccount) {
        // Pre-seed B (becomes inactive once A signs in), then sign in to A.
        registry.activate(url: try XCTUnwrap(URL(string: "https://b.test")))
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: keychain,
            clientFactory: { _ in MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: false)) },
            serverRegistry: registry
        )
        await manager.configure(serverURLString: "https://a.test", password: "")

        guard case .loggedIn = manager.state else {
            XCTFail("Expected loggedIn after configure, got \(manager.state)")
            throw PreconditionFailure()
        }

        let aAccount = try XCTUnwrap(registry.servers.first { $0.id == "https://a.test" })
        let bAccount = try XCTUnwrap(registry.servers.first { $0.id == "https://b.test" })
        return (manager, aAccount, bAccount)
    }

    private func makeLoggedInManager(
        keychain: InMemoryKeychainStore,
        serverURLString: String,
        client providedClient: MockAuthAPIClient? = nil,
        logoutTimeout: Duration = .seconds(5)
    ) async throws -> AuthManager {
        let client = providedClient
            ?? MockAuthAPIClient(authStatus: AuthStatusResponse(authEnabled: true, loggedIn: false))
        let manager = AuthManager(
            cookieStorage: cookieStorage,
            keychain: keychain,
            clientFactory: { _ in client },
            logoutTimeout: logoutTimeout,
            serverRegistry: ServerRegistry.inMemory()
        )

        await manager.configure(serverURLString: serverURLString, password: "secret")

        guard case .loggedIn = manager.state else {
            XCTFail("Expected loggedIn state after configure, got \(manager.state)")
            throw PreconditionFailure()
        }

        return manager
    }

    private func makeSessionCookie(for server: URL, value: String = "stale-session-token") throws -> HTTPCookie {
        try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: try XCTUnwrap(server.host),
                .path: "/",
                .name: "hermes_session",
                .value: value,
            ])
        )
    }
}
