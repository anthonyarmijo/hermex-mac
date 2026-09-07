import XCTest
@testable import HermesMobile

final class ConnectionStatusTests: APIClientTestCase {
    func testProbeSeparatesHealthyServerFromMissingAuthenticationAndVersions() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.timeoutInterval, 8)
            let body: String
            switch request.url?.path {
            case "/health": body = #"{"status":"ok","future_field":true}"#
            case "/api/auth/status": body = #"{"auth_enabled":true,"logged_in":false}"#
            case "/api/settings": body = #"{"future_setting":"ignored"}"#
            default: XCTFail("Unexpected diagnostic endpoint"); throw URLError(.badURL)
            }
            return apiTestJSONResponse(body, for: request)
        }
        let result = await ConnectionStatusProbe(client: client).check()
        XCTAssertGreaterThanOrEqual(try result.health.get(), 0)
        XCTAssertEqual(try result.authentication.get(), .required)
        XCTAssertEqual(try result.versions.get(), ConnectionVersions(webUI: nil, agent: nil))
    }

    func testProbeUsesExistingHeadersAndRejectsHTMLWithoutLeakingItsBody() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Proxy-Test"), "test-only-secret")
            if request.url?.path == "/api/auth/status" {
                return apiTestJSONResponse(#"{"auth_enabled":false}"#, for: request)
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/html"]))
            return (response, Data("<html>token=do-not-display</html>".utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: configuration),
            customHeaderProvider: { [CustomHeader(name: "X-Proxy-Test", value: "test-only-secret")] })
        let result = await ConnectionStatusProbe(client: client).check()
        XCTAssertEqual(result.health.failure, .unexpectedResponse)
        XCTAssertEqual(result.versions.failure, .unexpectedResponse)
        XCTAssertEqual(try result.authentication.get(), .notRequired)
    }

    func testURLDisplayRemovesCredentialsQueriesAndFragments() throws {
        let url = try XCTUnwrap(URL(string: "https://user:secret@example.test/base?unknown_credential=private#token"))
        XCTAssertEqual(ConnectionURLDisplay.sanitized(url), "https://example.test/base")
        for value in ["http://localhost:8787", "http://127.0.0.2:8787", "http://[::1]:8787"] {
            XCTAssertTrue(ConnectionURLDisplay.isLoopback(URL(string: value)))
        }
        XCTAssertFalse(ConnectionURLDisplay.isLoopback(URL(string: "https://localhost.example.test")))
        XCTAssertEqual(ConnectionURLDisplay.sanitized(nil), "")
    }

    func testErrorsAreActionableAndDoNotExposeRawServerOrNetworkText() {
        let cases: [(Error, ConnectionFailure)] = [
            (APIError.network(underlying: URLError(.cannotFindHost)), .dns),
            (URLError(.timedOut), .timeout),
            (URLError(.serverCertificateUntrusted), .tls),
            (APIError.unauthorized, .authentication),
            (APIError.http(statusCode: 403, body: "secret=private"), .http(403)),
            (APIError.decoding(underlying: URLError(.badServerResponse)), .unexpectedResponse)
        ]
        for (error, expected) in cases {
            let failure = ConnectionFailure.classify(error)
            XCTAssertEqual(failure, expected)
            XCTAssertFalse(failure.message.contains("secret=private"))
            XCTAssertFalse(failure.message.isEmpty)
        }
    }

    @MainActor
    func testUnconfiguredCheckDoesNotCreateClient() async {
        let model = ConnectionStatusModel { _ in XCTFail("No selected server"); return FixedConnectionProbe(result: .healthy) }
        await model.refresh()
        XCTAssertEqual(model.reachability, .unconfigured)
        XCTAssertNil(model.checkedAt)
    }

    @MainActor
    func testRepeatedChecksCoalesceAndServerSwitchRejectsLateResult() async {
        let first = ControlledConnectionProbe()
        let a = URL(string: "https://a.example.test")!
        let b = URL(string: "https://b.example.test")!
        let model = ConnectionStatusModel { server -> any ConnectionStatusChecking in
            if server == a { return first }
            return FixedConnectionProbe(result: .healthy)
        }
        model.select(server: a)
        let old = Task { await model.refresh() }
        await first.waitUntilStarted()
        let overlap = Task { await model.refresh() }
        await Task.yield()
        let callCount = await first.calls
        XCTAssertEqual(callCount, 1)
        model.select(server: b)
        XCTAssertNil(model.versions)
        await model.refresh()
        await first.finish(.offline)
        await old.value
        await overlap.value
        XCTAssertEqual(model.server, b)
        XCTAssertEqual(model.reachability, .reachable)
        XCTAssertEqual(model.versions?.webUI, "test-webui")
    }

    @MainActor
    func testFailedRefreshLabelsSameServerVersionsStaleAndResetsAuthentication() async {
        var next = ConnectionProbeResult.healthy
        let model = ConnectionStatusModel { _ in FixedConnectionProbe(result: next) }
        model.select(server: URL(string: "https://example.test"))
        await model.refresh()
        let versionDate = model.versionsCheckedAt
        next = .offline
        await model.refresh()
        XCTAssertEqual(model.reachability, .unreachable)
        XCTAssertEqual(model.authentication, .unknown)
        XCTAssertNil(model.latencyMilliseconds)
        XCTAssertTrue(model.versionsAreStale)
        XCTAssertEqual(model.versions?.webUI, "test-webui")
        XCTAssertEqual(model.versionsCheckedAt, versionDate)
        model.select(server: URL(string: "https://other.example.test"))
        XCTAssertNil(model.versions)
        XCTAssertNil(model.checkedAt)
        XCTAssertFalse(model.versionsAreStale)
    }

    @MainActor
    func testCancellationDoesNotPublishLateSuccess() async {
        let probe = ControlledConnectionProbe()
        let model = ConnectionStatusModel { _ in probe }
        model.select(server: URL(string: "https://example.test"))
        let work = Task { await model.refresh() }
        await probe.waitUntilStarted()
        model.cancel()
        await probe.finish(.healthy)
        await work.value
        XCTAssertNil(model.checkedAt)
        XCTAssertEqual(model.reachability, .notChecked)
    }
}

private extension Result where Failure == ConnectionFailure {
    var failure: ConnectionFailure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

private extension ConnectionProbeResult {
    static var healthy: Self {
        Self(health: .success(12), authentication: .success(.signedIn),
             versions: .success(ConnectionVersions(webUI: "test-webui", agent: "test-agent")))
    }
    static var offline: Self {
        Self(health: .failure(.timeout), authentication: .failure(.timeout), versions: .failure(.timeout))
    }
}

private struct FixedConnectionProbe: ConnectionStatusChecking {
    let result: ConnectionProbeResult
    func check() async -> ConnectionProbeResult { result }
}

private actor ControlledConnectionProbe: ConnectionStatusChecking {
    private(set) var calls = 0
    private var continuation: CheckedContinuation<ConnectionProbeResult, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    func check() async -> ConnectionProbeResult {
        calls += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            startWaiters.forEach { $0.resume() }
            startWaiters = []
        }
    }
    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func finish(_ result: ConnectionProbeResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
