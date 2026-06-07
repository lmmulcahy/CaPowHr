import SwiftUI

struct TrustedDevicesSettingsView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @State private var devices = TrustedDeviceStore.loadAll()

    var body: some View {
        List {
            if devices.isEmpty {
                Text("No trusted devices yet.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(devices) { device in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                        Text(device.deviceType.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            TrustedDeviceStore.forget(id: device.id)
                            devices = TrustedDeviceStore.loadAll()
                        } label: {
                            Text("Forget")
                        }
                    }
                }
            }

            Button("Reconnect Trusted Devices") {
                workoutManager.attemptReconnectToTrustedDevices()
            }
        }
        .navigationTitle("Trusted Devices")
        .onAppear { devices = TrustedDeviceStore.loadAll() }
    }
}

struct CompatibilityListView: View {
    @State private var records = CompatibilityStore.loadAll()

    var body: some View {
        List {
            if records.isEmpty {
                Text("Connect equipment to build your compatibility list.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.deviceName)
                        Text("\(record.deviceType.rawValue.capitalized) · \(record.successfulWorkoutCount) workouts")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Tested Equipment")
        .onAppear { records = CompatibilityStore.loadAll() }
    }
}

struct MetricsLayoutSettingsView: View {
    @State private var bikeMetrics = WorkoutMetricsLayout.bikeMetrics()
    @State private var treadmillMetrics = WorkoutMetricsLayout.treadmillMetrics()
    @State private var rowerMetrics = WorkoutMetricsLayout.rowerMetrics()

    var body: some View {
        List {
            Section("Bike Screen") {
                ForEach(bikeMetrics) { metric in
                    Text(metric.title)
                }
                .onMove { from, to in
                    bikeMetrics.move(fromOffsets: from, toOffset: to)
                    WorkoutMetricsLayout.saveBikeMetrics(bikeMetrics)
                }
            }
            Section("Treadmill Screen") {
                ForEach(treadmillMetrics) { metric in
                    Text(metric.title)
                }
                .onMove { from, to in
                    treadmillMetrics.move(fromOffsets: from, toOffset: to)
                    WorkoutMetricsLayout.saveTreadmillMetrics(treadmillMetrics)
                }
            }
            Section("Rower Screen") {
                ForEach(rowerMetrics) { metric in
                    Text(metric.title)
                }
                .onMove { from, to in
                    rowerMetrics.move(fromOffsets: from, toOffset: to)
                    WorkoutMetricsLayout.saveRowerMetrics(rowerMetrics)
                }
            }
        }
        .navigationTitle("Metric Layout")
    }
}

struct TrainingSettingsView: View {
    @State private var maxHR = AppSettings.maxHeartRate
    @State private var ftp = AppSettings.ftp
    @State private var template = StructuredWorkoutTemplate.free

    var body: some View {
        Form {
            Section("Heart Rate Zones") {
                Stepper("Max HR: \(maxHR)", value: $maxHR, in: 120...220)
            }
            Section("Power Zones") {
                Stepper("FTP: \(ftp) W", value: $ftp, in: 80...450, step: 5)
            }
            Section("Structured Workout") {
                Picker("Template", selection: $template) {
                    ForEach(StructuredWorkoutTemplate.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
            }
        }
        .navigationTitle("Training")
        .onChange(of: maxHR) { AppSettings.maxHeartRate = $0 }
        .onChange(of: ftp) { AppSettings.ftp = $0 }
        .onChange(of: template) {
            UserDefaults.standard.set(template.rawValue, forKey: AppSettings.structuredWorkoutTemplateKey)
        }
        .onAppear {
            maxHR = AppSettings.maxHeartRate
            ftp = AppSettings.ftp
            let raw = UserDefaults.standard.string(forKey: AppSettings.structuredWorkoutTemplateKey) ?? StructuredWorkoutTemplate.free.rawValue
            template = StructuredWorkoutTemplate(rawValue: raw) ?? .free
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TrainingSettingsView()
    }
}
#endif
