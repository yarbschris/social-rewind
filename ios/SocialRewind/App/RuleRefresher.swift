import Foundation
import RewindCore

/// Opt-in download of rule packs from the public GitHub repo (docs/decisions/0002).
/// Plain GET: no cookies, no cache, no identifiers.
struct RuleRefresher {
    enum Outcome: Sendable {
        case updated(LoadedRulePack)
        case upToDate
        case failed(String)
    }

    static let minimumInterval: TimeInterval = 6 * 60 * 60
    static let maxBytes = 512 * 1024

    func refresh(_ platform: Platform, current: LoadedRulePack) async -> Outcome {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: platform.rulePackRefreshURL)
        request.httpMethod = "GET"

        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("server returned \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            guard body.count <= Self.maxBytes else { return .failed("pack too large") }
            data = body
        } catch {
            return .failed("network error")
        }

        do {
            let accepted = try RulePackSelector.accept(data, over: current, platform: platform)
            try write(data, for: platform)
            return .updated(accepted)
        } catch RulePackSelector.RejectionReason.notNewer {
            return .upToDate
        } catch let reason as RulePackSelector.RejectionReason {
            return .failed("rejected (\(reason))")
        } catch {
            return .failed("couldn't save")
        }
    }

    private func write(_ data: Data, for platform: Platform) throws {
        guard let url = RulePackLoader.refreshedURL(platform) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
