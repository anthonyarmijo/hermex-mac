import Foundation
import Observation

/// Diagnostics deliberately never display raw HTTP bodies or underlying error
/// descriptions: either can contain a proxy token or a credential-bearing URL.
enum ConnectionFailure: Error, Equatable, Sendable {
    case dns, timeout, tls, network, authentication, unexpectedResponse, http(Int)

    static func classify(_ error: Error) -> Self {
        if let api = error as? APIError {
            switch api {
            case .network(let underlying): return classify(underlying)
            case .unauthorized: return .authentication
            case .http(let code, _): return code == 401 ? .authentication : .http(code)
            case .decoding, .invalidServerURL: return .unexpectedResponse
            }
        }
        switch (error as NSError).code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return .dns
        case NSURLErrorTimedOut: return .timeout
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired: return .tls
        default: return .network
        }
    }

    var message: String {
        switch self {
        case .dns: return String(localized: "The server name could not be found. Check the address and your network or private connection.")
        case .timeout: return String(localized: "The server took too long to respond. Check that the server machine is awake, then try again.")
        case .tls: return String(localized: "The secure connection could not be verified. Check the server certificate and address.")
        case .network: return String(localized: "The server could not be reached. Check that it is running and your network or private connection is available.")
        case .authentication: return String(localized: "Sign in to this server to check its protected settings.")
        case .unexpectedResponse: return String(localized: "The address responded, but the response was not the expected Hermes WebUI data. Check the server URL and compatibility.")
        case .http(let code): return String(localized: "The server returned HTTP \(code). Check the server or proxy configuration, then try again.")
        }
    }

    var receivedResponse: Bool {
        switch self {
        case .authentication, .unexpectedResponse, .http: return true
        default: return false
        }
    }
}

struct ConnectionVersions: Equatable, Sendable {
    let webUI: String?
    let agent: String?
}

enum ConnectionAuthentication: String, Sendable { case unknown, signedIn, required, notRequired }

struct ConnectionProbeResult: Sendable {
    let health: Result<Double, ConnectionFailure>
    let authentication: Result<ConnectionAuthentication, ConnectionFailure>
    let versions: Result<ConnectionVersions, ConnectionFailure>
}

protocol ConnectionStatusChecking: Sendable {
    func check() async -> ConnectionProbeResult
}

struct ConnectionStatusProbe: ConnectionStatusChecking {
    let client: APIClient

    func check() async -> ConnectionProbeResult {
        await withTaskGroup(of: ConnectionProbeResult.self) { group in
            group.addTask { await performCheck() }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return ConnectionProbeResult(health: .failure(.timeout), authentication: .failure(.timeout), versions: .failure(.timeout))
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func performCheck() async -> ConnectionProbeResult {
        async let health = checkHealth()
        async let authentication = checkAuthentication()
        async let versions = checkVersions()
        return await ConnectionProbeResult(health: health, authentication: authentication, versions: versions)
    }

    private func read<Value: Decodable>(_ endpoint: Endpoint, as type: Value.Type) async throws -> Value {
        let (data, response) = try await client.sendDataReturningResponse(
            endpoint: endpoint, method: "GET", encodedBody: nil, timeout: 8
        )
        guard response.mimeType?.lowercased() == "application/json" else {
            throw ConnectionFailure.unexpectedResponse
        }
        return try await client.decode(type, from: data)
    }

    private func failure(_ error: Error) -> ConnectionFailure {
        (error as? ConnectionFailure) ?? ConnectionFailure.classify(error)
    }

    private func checkHealth() async -> Result<Double, ConnectionFailure> {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let health = try await read(.health, as: HealthResponse.self)
            guard health.status?.lowercased() == "ok" else { return .failure(.unexpectedResponse) }
            let duration = start.duration(to: clock.now).components
            return .success(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
        } catch { return .failure(failure(error)) }
    }

    private func checkAuthentication() async -> Result<ConnectionAuthentication, ConnectionFailure> {
        do {
            let status = try await read(.authStatus, as: AuthStatusResponse.self)
            if status.authEnabled == false { return .success(.notRequired) }
            return .success(status.loggedIn == true ? .signedIn : status.loggedIn == false ? .required : .unknown)
        } catch { return .failure(failure(error)) }
    }

    private func checkVersions() async -> Result<ConnectionVersions, ConnectionFailure> {
        do {
            let settings = try await read(.settings, as: SettingsResponse.self)
            return .success(ConnectionVersions(webUI: settings.webuiVersion, agent: settings.agentVersion))
        } catch { return .failure(failure(error)) }
    }
}

enum ConnectionURLDisplay {
    static func sanitized(_ url: URL?) -> String {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        parts.user = nil
        parts.password = nil
        // Queries and fragments are not needed to identify a configured server.
        // Omitting all of them also covers unknown proxy credential names.
        parts.query = nil
        parts.fragment = nil
        return parts.string ?? ""
    }

    static func isLoopback(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else { return false }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        let isIPv4Loopback = octets.count == 4 && octets.first == "127"
            && octets.allSatisfy { Int($0).map { (0...255).contains($0) } == true }
        return host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || isIPv4Loopback
    }
}

@MainActor
@Observable
final class ConnectionStatusModel {
    enum Reachability: String { case unconfigured, notChecked, checking, reachable, unreachable }
    typealias Authentication = ConnectionAuthentication

    private(set) var server: URL?
    private(set) var reachability: Reachability = .unconfigured
    private(set) var authentication: Authentication = .unknown
    private(set) var latencyMilliseconds: Double?
    private(set) var checkedAt: Date?
    private(set) var versions: ConnectionVersions?
    private(set) var versionsCheckedAt: Date?
    private(set) var versionsAreStale = false
    private(set) var diagnostics: [ConnectionFailure] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let checker: (URL) -> any ConnectionStatusChecking

    init(checker: @escaping (URL) -> any ConnectionStatusChecking = { server in
        // Freeze the selected server's headers for this probe, so a registry
        // switch cannot lend the next server's headers to an older request.
        let headers = CustomHeaderStore.shared.snapshot()
        return ConnectionStatusProbe(client: APIClient(baseURL: server, customHeaderProvider: { headers }))
    }) { self.checker = checker }

    func select(server: URL?) {
        guard self.server != server else { return }
        cancel()
        self.server = server
        reachability = server == nil ? .unconfigured : .notChecked
        authentication = .unknown
        latencyMilliseconds = nil
        checkedAt = nil
        versions = nil
        versionsCheckedAt = nil
        versionsAreStale = false
        diagnostics = []
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        if reachability == .checking { reachability = server == nil ? .unconfigured : .notChecked }
    }

    func refresh() async {
        if let task { await task.value; return }
        guard let server else { return }
        reachability = .checking
        let token = generation
        let probe = checker(server)
        let work = Task { [weak self] in
            let result = await probe.check()
            guard let self, !Task.isCancelled, token == self.generation, self.server == server else { return }
            self.apply(result)
            self.task = nil
        }
        task = work
        await work.value
    }

    private func apply(_ result: ConnectionProbeResult) {
        checkedAt = Date()
        diagnostics = []
        func record(_ failure: ConnectionFailure) {
            if !diagnostics.contains(failure) { diagnostics.append(failure) }
        }
        switch result.health {
        case .success(let milliseconds): reachability = .reachable; latencyMilliseconds = milliseconds
        case .failure(let failure):
            reachability = failure.receivedResponse ? .reachable : .unreachable
            latencyMilliseconds = nil
            record(failure)
        }
        switch result.authentication {
        case .success(let status): authentication = status
        case .failure(let failure): authentication = failure == .authentication ? .required : .unknown; record(failure)
        }
        switch result.versions {
        case .success(let value): versions = value; versionsCheckedAt = checkedAt; versionsAreStale = false
        case .failure(let failure):
            versionsAreStale = versions != nil
            if failure == .authentication { authentication = .required }
            record(failure)
        }
    }
}
