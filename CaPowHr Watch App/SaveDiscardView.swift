import SwiftUI

struct SaveDiscardView: View {
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        VStack(spacing: 8) {
            if workoutManager.isEndingCollection {
                // Processing indicator - show only when processing
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                    Text("Processing workout...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            } else {
                // Buttons - show only when not processing
                // Top discard button
                Button(action: {
                    workoutManager.discardCurrentWorkout()
                }) {
                    Text("Discard Workout")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer(minLength: 12)
                
                // Bottom save button
                Button(action: {
                    workoutManager.confirmSaveWorkout()
                }) {
                    Text("Save Workout")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 6)
    }
}

#if DEBUG
#Preview {
    let wm = WorkoutManager()
    wm.isAwaitingSave = true
    return SaveDiscardView(workoutManager: wm)
}
#endif


