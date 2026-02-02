//
//  DeviceConnectionView.swift
//  CaPowHr Watch App
//
//  Created by Luke Mulcahy on 2/1/26.
//

import SwiftUI

struct DeviceConnectionView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @Binding var isPresented: Bool
    
    var body: some View {
        List {
            Section(header: Text("Available Devices")) {
                if workoutManager.scannedDevices.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Scanning...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(workoutManager.scannedDevices) { device in
                        Button {
                            workoutManager.connect(to: device)
                            isPresented = false
                        } label: {
                            HStack {
                                Image(systemName: device.iconName)
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                        .font(.body)
                                    Text("Signal: \(device.rssi)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Only start scanning if no devices already present (allows previews to work)
            if workoutManager.scannedDevices.isEmpty {
                workoutManager.startScanning()
            }
        }
        .onDisappear {
            workoutManager.stopScanning()
        }
    }
}

#if DEBUG
#Preview("Scanning") {
    @Previewable @State var isPresented = true
    let wm = WorkoutManager()
    return DeviceConnectionView(workoutManager: wm, isPresented: $isPresented)
}

#Preview("Treadmill") {
    @Previewable @State var isPresented = true
    let wm = WorkoutManager()
    wm.scannedDevices = [
        ScannedDevice(id: UUID(), name: "NordicTrack T9.5", rssi: -65, iconName: "figure.run")
    ]
    return DeviceConnectionView(workoutManager: wm, isPresented: $isPresented)
}

#Preview("Indoor Bike") {
    @Previewable @State var isPresented = true
    let wm = WorkoutManager()
    wm.scannedDevices = [
        ScannedDevice(id: UUID(), name: "ICSE", rssi: -55, iconName: "bicycle")
    ]
    return DeviceConnectionView(workoutManager: wm, isPresented: $isPresented)
}

#Preview("Rower") {
    @Previewable @State var isPresented = true
    let wm = WorkoutManager()
    wm.scannedDevices = [
        ScannedDevice(id: UUID(), name: "WaterRower S4", rssi: -70, iconName: "oar.2.crossed")
    ]
    return DeviceConnectionView(workoutManager: wm, isPresented: $isPresented)
}

#Preview("Cross Trainer") {
    @Previewable @State var isPresented = true
    let wm = WorkoutManager()
    wm.scannedDevices = [
        ScannedDevice(id: UUID(), name: "ProForm Elliptical", rssi: -60, iconName: "figure.elliptical")
    ]
    return DeviceConnectionView(workoutManager: wm, isPresented: $isPresented)
}

#Preview("Stair Climber") {
    @Previewable @State var isPresented = true
    let wm = WorkoutManager()
    wm.scannedDevices = [
        ScannedDevice(id: UUID(), name: "StairMaster 4G", rssi: -58, iconName: "figure.stairs")
    ]
    return DeviceConnectionView(workoutManager: wm, isPresented: $isPresented)
}

#Preview("Generic FTMS") {
    @Previewable @State var isPresented = true
    let wm = WorkoutManager()
    wm.scannedDevices = [
        ScannedDevice(id: UUID(), name: "A4:C1:38:XX:XX:XX", rssi: -72, iconName: "figure.mixed.cardio")
    ]
    return DeviceConnectionView(workoutManager: wm, isPresented: $isPresented)
}

#Preview("Multiple Devices") {
    @Previewable @State var isPresented = true
    let wm = WorkoutManager()
    wm.scannedDevices = [
        ScannedDevice(id: UUID(), name: "ICSE", rssi: -55, iconName: "bicycle"),
        ScannedDevice(id: UUID(), name: "NordicTrack T9.5", rssi: -65, iconName: "figure.run"),
        ScannedDevice(id: UUID(), name: "WaterRower S4", rssi: -70, iconName: "oar.2.crossed"),
        ScannedDevice(id: UUID(), name: "Unknown Device", rssi: -80, iconName: "sensor.fill")
    ]
    return DeviceConnectionView(workoutManager: wm, isPresented: $isPresented)
}
#endif
