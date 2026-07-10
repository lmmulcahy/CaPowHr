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
