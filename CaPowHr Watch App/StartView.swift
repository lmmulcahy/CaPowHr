import SwiftUI

struct StartView: View {
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "bicycle")
                    .foregroundColor(.green)
                Text("CaPowHr")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .padding(.top, 4)
            
            if workoutManager.connectedDevices.isEmpty {
                Text("No sensors connected")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            } else {
                Text("Connected: \(workoutManager.connectedDevices.joined(separator: ", "))")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.green)
                    .padding(.horizontal, 4)
            }
            
            Button("Connect Sensors") {
                workoutManager.startScanningForTesting()
            }
            .font(.subheadline)
            .foregroundColor(.blue)

            Spacer(minLength: 6)

            Button(action: {
                workoutManager.startWorkout()
            }) {
                Text("Start")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: 150)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

#if DEBUG
#Preview("No Devices") {
    let wm = WorkoutManager()
    return StartView(workoutManager: wm)
}

#Preview("With Devices") {
    let wm = WorkoutManager()
    wm.connectedDevices = ["ICSE"]
    return StartView(workoutManager: wm)
}
#endif


