import SwiftUI
import CoreBluetooth

/// Standalone BLE log capture flow for diagnostic uploads.
/// This view reuses the app's existing Bluetooth stack (via WorkoutManager) to reliably connect
/// even when sensors start disconnected.
struct BLELogCaptureView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @StateObject private var viewModel: BLELogCaptureViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(workoutManager: WorkoutManager) {
        self.workoutManager = workoutManager
        _viewModel = StateObject(wrappedValue: BLELogCaptureViewModel(workoutManager: workoutManager))
    }
    
    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .disconnecting:
                progressView(message: "Disconnecting…")
            case .connecting:
                connectingView
            case .countdown(let remaining):
                countdownView(remaining: remaining)
            case .captured:
                capturedView
            case .uploading:
                progressView(message: "Uploading…")
            case .success(let url):
                successView(url: url)
            case .failure(let message):
                failureView(message: message)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: workoutManager.connectedDevices) { _, newValue in
            viewModel.updateConnectedDevices(newValue)
        }
    }
    
    // MARK: - Subviews
    
    private var idleView: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    Text("BLE Log Capture")
                        .font(.headline)
                }
                
                Text("This will connect to your sensors and record 20 seconds of data for diagnostic upload.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    viewModel.startCapture()
                } label: {
                    Label("Start Capture", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    
    private func progressView(message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    
    private var connectingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Connecting to sensors…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            if !viewModel.connectedDevices.isEmpty {
                Text("Connected: \(viewModel.connectedDevices.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            
            Button("Cancel") {
                viewModel.cancel()
            }
            .font(.footnote)
            .foregroundStyle(.red)
        }
    }
    
    private func countdownView(remaining: Int) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / 20.0)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                
                Text("\(remaining)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }
            .frame(width: 100, height: 100)
            
            Text("Pedal now!")
                .font(.headline)
                .foregroundStyle(.primary)
            
            if !viewModel.connectedDevices.isEmpty {
                Text(viewModel.connectedDevices.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Button("Cancel") {
                viewModel.cancel()
            }
            .font(.footnote)
            .foregroundStyle(.red)
        }
    }
    
    private var capturedView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                
                Text("Log Captured!")
                    .font(.headline)
                
                Text("Ready to upload for diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                if let tokenError = viewModel.tokenErrorMessage {
                    Text(tokenError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else if viewModel.hasToken {
                    Button {
                        viewModel.uploadLog()
                    } label: {
                        Label("Upload Log", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("No GitHub token configured.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                
                Button("Discard") {
                    viewModel.discard()
                    dismiss()
                }
                .font(.footnote)
                .foregroundStyle(.red)
            }
            .padding()
        }
    }
    
    private func successView(url: URL) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                
                Text("Upload Complete!")
                    .font(.headline)
                
                Button("Done") {
                    dismiss()
                }
                .font(.footnote)
            }
            .padding()
        }
    }
    
    private func failureView(message: String) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                
                Text("Upload Failed")
                    .font(.headline)
                
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Retry") {
                    viewModel.uploadLog()
                }
                .font(.footnote)
                
                Button("Discard & Go Back") {
                    viewModel.discard()
                    dismiss()
                }
                .font(.footnote)
                .foregroundStyle(.red)
            }
            .padding()
        }
    }
}

// MARK: - ViewModel

@MainActor
final class BLELogCaptureViewModel: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case disconnecting
        case connecting
        case countdown(remaining: Int)
        case captured
        case uploading
        case success(URL)
        case failure(String)
    }
    
    @Published private(set) var state: State = .idle
    @Published private(set) var connectedDevices: [String] = []
    @Published private(set) var hasToken: Bool = false
    @Published private(set) var tokenErrorMessage: String?
    
    private let workoutManager: WorkoutManager
    private let bleLog = BluetoothLogManager.shared
    private let client = GitHubIssueClient()
    
    private var countdownTimer: Timer?
    private var countdownRemaining: Int = 20
    private var capturedLogURL: URL?
    
    private var savedToken: String = ""
    private let keychain = KeychainStore(service: "com.capowhr.github")
    private let keychainAccount = "githubToken"
    
    init(workoutManager: WorkoutManager) {
        self.workoutManager = workoutManager
        super.init()
        loadToken()
    }
    
    private func loadToken() {
        do {
            if let saved = try keychain.readString(account: keychainAccount), !saved.isEmpty {
                savedToken = saved
                hasToken = true
            } else if let bundled = readBundledToken(), !bundled.isEmpty {
                savedToken = bundled
                hasToken = true
            } else {
                savedToken = ""
                hasToken = false
            }
            tokenErrorMessage = nil
        } catch {
            tokenErrorMessage = error.localizedDescription
            savedToken = ""
            hasToken = false
        }
    }
    
    private func readBundledToken() -> String? {
        let keys = ["CaPowHrGitHubToken", "INFOPLIST_KEY_CaPowHrGitHubToken", "CAPOWHR_GITHUB_TOKEN"]
        for key in keys {
            if let v = Bundle.main.object(forInfoDictionaryKey: key) as? String {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return nil
    }
    
    func startCapture() {
        state = .disconnecting

        // Best effort: ensure we start from a clean/disconnected state.
        workoutManager.disconnectSensors()

        // Start logging (BluetoothManager will emit log records while connected).
        bleLog.startSession(
            reason: "diagnostic_capture",
            appContext: Self.makeAppContext()
        )

        // Give a moment for disconnect to propagate, then begin scanning/connecting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.state = .connecting
            self.workoutManager.startScanning()
            self.updateConnectedDevices(self.workoutManager.connectedDevices)
        }
    }
    
    func cancel() {
        stopCapture()
        bleLog.endSession(reason: "diagnostic_capture_cancelled")
        state = .idle
    }
    
    func discard() {
        stopCapture()
        // Session was already ended when capture completed or cancelled
    }
    
    func uploadLog() {
        guard hasToken else {
            state = .failure("No GitHub token available.")
            return
        }
        
        guard let loaded = bleLog.loadLatestLogText() else {
            state = .failure("No BLE log found.")
            return
        }
        
        state = .uploading
        
        Task {
            await performUpload(loaded: loaded)
        }
    }
    
    private func performUpload(loaded: (text: String, wasTruncated: Bool, filename: String)) async {
        let title = "BLE diagnostic log: \(loaded.filename)"
        
        var body = """
        Automated BLE diagnostic log upload from CaPowHr (watch).

        Log file: \(loaded.filename)
        Truncated: \(loaded.wasTruncated ? "yes" : "no")

        ```jsonl
        \(loaded.text)
        ```
        """
        
        if body.count > 60_000 {
            body = String(body.suffix(60_000))
        }
        
        do {
            let url = try await client.createIssue(
                owner: "lmmulcahy",
                repo: "CaPowHrPublic",
                title: title,
                body: body,
                labels: ["ble-log", "diagnostic"],
                token: savedToken.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            state = .success(url)
        } catch {
            state = .failure(error.localizedDescription)
        }
    }
    
    private func stopCapture() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        workoutManager.disconnectSensors()
        connectedDevices = workoutManager.connectedDevices
    }
    
    private func startCountdown() {
        countdownRemaining = 20
        state = .countdown(remaining: countdownRemaining)
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickCountdown()
            }
        }
    }
    
    private func tickCountdown() {
        countdownRemaining -= 1
        
        if countdownRemaining <= 0 {
            countdownTimer?.invalidate()
            countdownTimer = nil
            finishCapture()
        } else {
            state = .countdown(remaining: countdownRemaining)
        }
    }
    
    private func finishCapture() {
        bleLog.endSession(reason: "diagnostic_capture_complete")
        capturedLogURL = bleLog.latestLogFileURL
        stopCapture()
        state = .captured
    }
    
    private static func makeAppContext() -> [String: String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return [
            "app": "CaPowHr",
            "version": version,
            "build": build,
            "platform": "watchOS",
            "captureType": "diagnostic"
        ]
    }
}

// MARK: - BluetoothManagerDelegate

extension BLELogCaptureViewModel {
    func updateConnectedDevices(_ names: [String]) {
        connectedDevices = names
        if !names.isEmpty, case .connecting = state {
            startCountdown()
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BLELogCaptureView(workoutManager: WorkoutManager())
    }
}
#endif

