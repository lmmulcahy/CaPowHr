import SwiftUI

struct GitHubUploadView: View {
    @ObservedObject private var bleLog = BluetoothLogManager.shared
    @StateObject private var uploader = GitHubLogUploadViewModel()

    @State private var savedToken: String = ""
    @State private var tokenSourceLabel: String = ""
    @State private var tokenErrorMessage: String?

    private let keychain = KeychainStore(service: "com.capowhr.github")
    private let keychainAccount = "githubToken"
    private let bundledTokenInfoPlistKey = "CaPowHrGitHubToken"
    private let bundledTokenInfoPlistKeyFallbacks = [
        // Some Xcode setups may leave the prefix in the generated Info.plist for custom keys.
        "INFOPLIST_KEY_CaPowHrGitHubToken",
        // If you ever choose to store it directly under the var name:
        "CAPOWHR_GITHUB_TOKEN"
    ]

    var body: some View {
        VStack(spacing: 8) {
            Text("GitHub Upload")
                .font(.headline)

            Button {
                Task { await uploader.uploadLatestBLELog(token: savedToken) }
            } label: {
                Text("Upload latest BLE log")
                    .font(.footnote)
            }
            .disabled(bleLog.latestLogFileURL == nil || savedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUploading)

            if let tokenErrorMessage {
                Text(tokenErrorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .lineLimit(3)
            } else if !savedToken.isEmpty {
                Text("Token source: \(tokenSourceLabel)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Text("Missing token. Set CAPOWHR_GITHUB_TOKEN in Config/Secrets.xcconfig, then Clean Build Folder + run again.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }

            switch uploader.state {
            case .idle:
                EmptyView()
            case .uploading:
                Text("Uploading…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            case let .success(url):
                Link("Issue created (open)", destination: url)
                    .font(.footnote)
                Button("Clear status") { uploader.reset() }
                    .font(.footnote)
            case let .failure(message):
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .lineLimit(4)
                Button("Clear status") { uploader.reset() }
                    .font(.footnote)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .onAppear { hydrateTokenState() }
    }

    private var isUploading: Bool {
        if case .uploading = uploader.state { return true }
        return false
    }

    private func hydrateTokenState() {
        do {
            let saved = try keychain.readString(account: keychainAccount)
            if let saved, !saved.isEmpty {
                savedToken = saved
                tokenSourceLabel = "Keychain"
            } else if let bundled = readBundledToken(), !bundled.isEmpty {
                savedToken = bundled
                tokenSourceLabel = "Bundled"
            } else {
                savedToken = ""
                tokenSourceLabel = ""
            }
            tokenErrorMessage = nil
        } catch {
            tokenErrorMessage = error.localizedDescription
            savedToken = ""
            tokenSourceLabel = ""
        }
    }

    private func readBundledToken() -> String? {
        // Primary key
        if let v = Bundle.main.object(forInfoDictionaryKey: bundledTokenInfoPlistKey) as? String {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }

        // Fallback keys
        for key in bundledTokenInfoPlistKeyFallbacks {
            if let v = Bundle.main.object(forInfoDictionaryKey: key) as? String {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }

        // As a last resort, scan the infoDictionary (sometimes values come through as non-String types).
        if let dict = Bundle.main.infoDictionary {
            for key in [bundledTokenInfoPlistKey] + bundledTokenInfoPlistKeyFallbacks {
                if let any = dict[key] {
                    let t = String(describing: any).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return t }
                }
            }
        }

        return nil
    }
}

#if DEBUG
#Preview {
    GitHubUploadView()
}
#endif


