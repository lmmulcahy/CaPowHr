import SwiftUI

struct SaveDiscardView: View {
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        ZStack {
            // Processing indicator - overlaid when processing
            if workoutManager.isEndingCollection {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                    Text("Processing workout...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Buttons - always in the hierarchy, but disabled when processing
            VStack(spacing: 8) {
                // Top discard button
                Button("Discard Workout") {
                    workoutManager.discardCurrentWorkout()
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.red)
                .disabled(workoutManager.isEndingCollection)
                
                Spacer(minLength: 12)
                
                // Bottom save button
                Button("Save Workout") {
                    workoutManager.confirmSaveWorkout()
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.green)
                .disabled(workoutManager.isEndingCollection)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 6)
            .opacity(workoutManager.isEndingCollection ? 0 : 1)
        }
    }
}

#if DEBUG
#Preview {
    let wm = WorkoutManager()
    wm.isAwaitingSave = true
    return SaveDiscardView(workoutManager: wm)
}
#endif


