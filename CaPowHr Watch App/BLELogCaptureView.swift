import SwiftUI
import CoreBluetooth
import UniformTypeIdentifiers

/// Standalone BLE log capture flow for diagnostics; the captured log is shared via the share sheet.
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
            case .captured(let logURL):
                capturedView(logURL: logURL)
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
                
                Text("This will connect to your sensors and record 20 seconds of data you can share for diagnostics.")
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
    
    private func capturedView(logURL: URL) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                
                Text("Log Captured!")
                    .font(.headline)
                
                Text("Share it via Messages or Mail for diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                ShareLink(
                    item: BLELogExport(url: logURL),
                    preview: SharePreview(logURL.lastPathComponent)
                ) {
                    Label("Share Log", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                
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
                
                Text("Capture Failed")
                    .font(.headline)
                
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Back") {
                    viewModel.reset()
                }
                .font(.footnote)
            }
            .padding()
        }
    }
}

// MARK: - Share Representation

/// A captured BLE log, offered to the share sheet as a .jsonl file with a plain-text fallback
/// for destinations that only accept text.
struct BLELogExport: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            SentTransferredFile(export.url)
        }
        ProxyRepresentation { export in
            String(decoding: try Data(contentsOf: export.url), as: UTF8.self)
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
        case captured(URL)
        case failure(String)
    }
    
    @Published private(set) var state: State = .idle
    @Published private(set) var connectedDevices: [String] = []
    
    private let workoutManager: WorkoutManager
    private let bleLog = BluetoothLogManager.shared
    
    private var countdownTimer: Timer?
    private var countdownRemaining: Int = 20
    
    init(workoutManager: WorkoutManager) {
        self.workoutManager = workoutManager
        super.init()
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
    
    func reset() {
        state = .idle
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
        stopCapture()
        if let url = bleLog.latestLogFileURL {
            state = .captured(url)
        } else {
            state = .failure(bleLog.lastErrorMessage ?? "No BLE log file was written.")
        }
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

