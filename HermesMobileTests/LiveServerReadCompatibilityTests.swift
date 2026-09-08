import Foundation
import XCTest
@testable import HermesMobile

/// Explicitly opted-in reads through production decoders. Uses an ephemeral
/// cookie jar and never edits an existing session, setting, file or task.
final class LiveServerReadCompatibilityTests: XCTestCase {
    private struct Configuration: Decodable {
        let serverURL: URL
        let password: String?
    }
    private struct Check: Codable {
        let endpoint: String
        let result: String
    }
    private struct Report: Encodable {
        let checkedAt: Date
        let webuiVersion: String?
        let agentVersion: String?
        let checks: [Check]
    }

    func testOptInReadOnlyCompatibility() async throws {
        guard ProcessInfo.processInfo.environment["HERMEX_RUN_LIVE_READ_COMPATIBILITY"] == "1" else {
            throw XCTSkip("Use the explicit HermesReadOnlyCompatibility scheme and an ignored local configuration.")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let configURL = root.appendingPathComponent(".codex-tmp/live-read-config.json")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Configuration.self, from: data) else {
            XCTFail("The ignored read-compatibility configuration is missing or invalid.")
            return
        }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 12
        sessionConfig.timeoutIntervalForResource = 20
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        let client = APIClient(baseURL: config.serverURL, session: session,
                               publicMediaSession: session, customHeaderProvider: { [] })
        var checks: [Check] = []
        var webuiVersion: String?, agentVersion: String?
        var selectedSession: String?, selectedSkill: String?, selectedJob: String?

        func check(_ label: String, required: Bool = false, _ operation: () async throws -> Void) async {
            do {
                try await operation()
                checks.append(Check(endpoint: label, result: "decoded"))
            } catch {
                let category: String
                switch error {
                case APIError.unauthorized: category = "authentication_required"
                case APIError.http(let status, _): category = "http_\(status)"
                case APIError.decoding: category = "decoding_failed"
                case APIError.network: category = "network_failed"
                default: category = "unavailable"
                }
                checks.append(Check(endpoint: label, result: category))
                // Never include error descriptions, response bodies, IDs or URLs.
                if required { XCTFail("Required read failed: \(label) (\(category))") }
            }
        }

        do {
            let status = try await client.authStatus()
            if status.authEnabled == true, !status.isAlreadySignedIn {
                guard let password = config.password, !password.isEmpty else {
                    XCTFail("Read check needs an isolated password login."); return
                }
                let login = try await client.login(password: password)
                guard login.ok == true else { XCTFail("Isolated read-check login failed."); return }
            }
        } catch { XCTFail("Could not establish isolated read-check authentication."); return }

        await check("health", required: true) {
            guard try await client.health().status == "ok" else { throw APIError.decoding(underlying: CocoaError(.coderReadCorrupt)) }
        }
        await check("auth/status", required: true) { _ = try await client.authStatus() }
        await check("settings", required: true) {
            let settings = try await client.settings()
            webuiVersion = settings.webuiVersion; agentVersion = settings.agentVersion
        }
        await check("sessions", required: true) {
            selectedSession = try await client.sessions().sessions?.compactMap(\.sessionId).first
        }
        await check("models", required: true) { _ = try await client.models() }
        await check("providers", required: true) { _ = try await client.providers() }
        await check("reasoning", required: true) { _ = try await client.reasoning() }
        await check("profiles", required: true) { _ = try await client.profiles() }
        await check("personalities", required: true) { _ = try await client.personalities() }
        await check("commands", required: true) { _ = try await client.commands() }
        await check("workspaces", required: true) { _ = try await client.workspaces() }
        await check("crons", required: true) {
            selectedJob = try await client.crons().jobs?.first?.id
        }
        await check("crons/status", required: true) { _ = try await client.cronStatus() }
        await check("crons/recent") { _ = try await client.cronRecent() }
        await check("crons/delivery-options") { _ = try await client.cronDeliveryOptions() }
        await check("skills", required: true) { selectedSkill = try await client.skills().skills?.compactMap(\.name).first }
        await check("memory", required: true) { _ = try await client.memory() }
        await check("insights") { _ = try await client.insights(days: 7) }
        await check("kanban/configuration") { _ = try await client.kanbanConfiguration() }
        await check("kanban/boards") { _ = try await client.kanbanBoards() }
        if let selectedSession {
            await check("session", required: true) { _ = try await client.session(id: selectedSession, includeMessages: false) }
            await check("session/status") { _ = try await client.sessionStatus(id: selectedSession) }
            await check("files") { _ = try await client.directoryList(sessionID: selectedSession) }
            await check("git-info") { _ = try await client.gitInfo(sessionID: selectedSession) }
            await check("git/status") { _ = try await client.gitStatus(sessionID: selectedSession) }
        } else { checks.append(Check(endpoint: "session-dependent reads", result: "skipped_no_session")) }
        if let selectedSkill {
            await check("skills/content", required: true) { _ = try await client.skillContent(name: selectedSkill) }
        } else { checks.append(Check(endpoint: "skills/content", result: "skipped_no_skill")) }
        if let selectedJob {
            await check("crons/output", required: true) { _ = try await client.cronOutput(jobID: selectedJob, limit: 1) }
        } else { checks.append(Check(endpoint: "crons/output", result: "skipped_no_job")) }
        checks.append(Check(endpoint: "file content/raw", result: "skipped_requires_selected_safe_file"))
        let report = Report(checkedAt: Date(), webuiVersion: webuiVersion, agentVersion: agentVersion, checks: checks)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let reportData = try encoder.encode(report)
        XCTContext.runActivity(named: "Sanitized read compatibility report") { activity in
            let attachment = XCTAttachment(data: reportData, uniformTypeIdentifier: "public.json")
            attachment.name = "read-compatibility.json"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        print("[READ-COMPAT-REPORT] \(String(decoding: reportData, as: UTF8.self))")
        for check in checks { print("[READ-COMPAT] \(check.endpoint): \(check.result)") }
    }
}
