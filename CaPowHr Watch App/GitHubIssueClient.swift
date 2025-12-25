import Foundation

enum GitHubIssueClientError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case missingHTMLURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub API: invalid response."
        case let .httpError(statusCode, message):
            if let message, !message.isEmpty {
                return "GitHub API error (\(statusCode)): \(message)"
            }
            return "GitHub API error (\(statusCode))."
        case .missingHTMLURL:
            return "GitHub API: issue created but missing URL."
        }
    }
}

final class GitHubIssueClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    struct CreateIssueRequest: Encodable {
        let title: String
        let body: String
        let labels: [String]?
    }

    struct CreateIssueResponse: Decodable {
        let html_url: String?
    }

    func createIssue(
        owner: String,
        repo: String,
        title: String,
        body: String,
        labels: [String]? = nil,
        token: String
    ) async throws -> URL {
        let endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/issues")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CreateIssueRequest(title: title, body: body, labels: labels)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubIssueClientError.invalidResponse }

        if !(200...299).contains(http.statusCode) {
            let message = Self.extractGitHubMessage(from: data)
            throw GitHubIssueClientError.httpError(statusCode: http.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(CreateIssueResponse.self, from: data)
        guard let html = decoded.html_url, let url = URL(string: html) else {
            throw GitHubIssueClientError.missingHTMLURL
        }
        return url
    }

    private static func extractGitHubMessage(from data: Data) -> String? {
        // Best-effort parse: { "message": "..." }
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = obj["message"] as? String
        else { return nil }
        return message
    }
}


