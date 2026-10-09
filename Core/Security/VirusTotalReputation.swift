import Foundation

enum ReputationTarget: Equatable, Sendable {
    case url(String), fileHash(String)
    var sharedValue: String {
        switch self { case .url(let value), .fileHash(let value): value }
    }
    var path: String {
        switch self {
        case .url(let value): "urls/" + Base64URL.encode(Data(value.utf8))
        case .fileHash(let value): "files/" + value
        }
    }
}

enum ReputationError: LocalizedError {
    case invalidTarget, missingKey, http(Int), invalidResponse, wait
    var errorDescription: String? {
        switch self {
        case .invalidTarget: "This is not a valid HTTP(S) URL or SHA-256 hash."
        case .missingKey: "Enter your VirusTotal API key to request an optional lookup."
        case .http(let code): "VirusTotal returned HTTP \(code). No reputation verdict is available. 404 means no existing report; 401/403 means API access failed; 429 means the rate limit was reached."
        case .invalidResponse: "VirusTotal did not return a usable report. Reputation remains unknown."
        case .wait: "Wait at least 15 seconds between lookups to respect the public API limit."
        }
    }
}

/// GET reports only. No upload, scan submission, rescan, or email-body endpoint exists here.
actor VirusTotalReputation {
    private var lastRequest: Date?
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: NoReputationRedirects(), delegateQueue: nil)
    }
    func lookup(_ target: ReputationTarget, apiKey: String) async throws -> SecurityFinding {
        let request = try Self.request(target, apiKey: apiKey)
        let now = Date()
        if let lastRequest, now.timeIntervalSince(lastRequest) < 15 { throw ReputationError.wait }
        lastRequest = now
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ReputationError.invalidResponse }
        guard response.statusCode == 200 else { throw ReputationError.http(response.statusCode) }
        return try Self.parse(data, now: now)
    }
    nonisolated static func request(_ target: ReputationTarget, apiKey: String) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isNewline }) else { throw ReputationError.missingKey }
        switch target {
        case .url(let value):
            guard value.utf8.count <= 8192, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
                  url.user == nil, url.password == nil else { throw ReputationError.invalidTarget }
        case .fileHash(let value):
            guard value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw ReputationError.invalidTarget }
        }
        let url = URL(string: "https://www.virustotal.com/api/v3/" + target.path)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.setValue(key, forHTTPHeaderField: "x-apikey")
        return request
    }
    nonisolated static func parse(_ data: Data, now: Date) throws -> SecurityFinding {
        struct Report: Decodable {
            struct Entry: Decodable {
                struct Attributes: Decodable {
                    let last_analysis_stats: [String: Int]?
                    let last_analysis_date: Double?
                }
                let attributes: Attributes
            }
            let data: Entry
        }
        guard let report = try? JSONDecoder().decode(Report.self, from: data),
              let stats = report.data.attributes.last_analysis_stats,
              let malicious = stats["malicious"], let suspicious = stats["suspicious"],
              malicious >= 0, suspicious >= 0, stats.values.allSatisfy({ $0 >= 0 && $0 <= 1_000_000 }), stats.count <= 32,
              stats.values.reduce(0, +) > 0 else { throw ReputationError.invalidResponse }
        let timestamp = report.data.attributes.last_analysis_date
        let date = timestamp.map { Date(timeIntervalSince1970: $0) }
        let fresh = date.map { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 7 * 86400 } ?? false
        let flagged = malicious + suspicious > 0
        let verdict: SecurityVerdict = flagged ? .concern : (fresh ? .checked : .unknown)
        let dateText = date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "unknown"
        return SecurityFinding(id: "virustotal", title: "VirusTotal reputation", verdict: verdict,
            explanation: "Existing report: \(malicious) malicious and \(suspicious) suspicious engine results. Analysis date: \(dateText). " +
                (flagged ? "One or more engines flagged this item; false positives are possible." : fresh ? "No engine detections were reported. This is not proof of safety or a fresh scan." : "Report is older than seven days or lacks a valid date; reputation remains unknown."), points: flagged ? 50 : 0)
    }
}

private final class NoReputationRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the API key or lookup to another destination.
    }
}
