import Foundation

@MainActor
final class GitHubLogUploadViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case uploading
        case success(URL)
        case failure(String)
    }

    @Published private(set) var state: State = .idle

    private let client: GitHubIssueClient

    init(client: GitHubIssueClient = GitHubIssueClient()) {
        self.client = client
    }

    func uploadLatestBLELog(token: String) async {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .failure("Missing GitHub token.")
            return
        }

        guard let loaded = BluetoothLogManager.shared.loadLatestLogText() else {
            state = .failure("No BLE log found yet.")
            return
        }

        state = .uploading

        let title = "BLE log: \(loaded.filename)"

        var body = """
        Automated BLE log upload from CaPowHr (watch).

        Log file: \(loaded.filename)
        Truncated: \(loaded.wasTruncated ? "yes" : "no")

        ```jsonl
        \(loaded.text)
        ```
        """

        // Extra safety in case the log text still pushes the body large.
        if body.count > 60_000 {
            let suffix = body.suffix(60_000)
            body = String(suffix)
        }

        do {
            let url = try await client.createIssue(
                owner: "lmmulcahy",
                repo: "CaPowHrPublic",
                title: title,
                body: body,
                labels: ["ble-log"],
                token: token.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            state = .success(url)
        } catch {
            state = .failure(error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
    }
}


