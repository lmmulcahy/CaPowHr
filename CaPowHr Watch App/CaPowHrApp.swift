//
//  CaPowHrApp.swift
//  CaPowHr Watch App
//

import SwiftUI

@main
struct CaPowHr_Watch_AppApp: App {
    @StateObject private var workoutManager = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environmentObject(workoutManager)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "capowhr", url.host == "start" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let typeRaw = components?.queryItems?.first(where: { $0.name == "type" })?.value ?? "indoorCycle"
        let workoutType = WorkoutType(rawValue: typeRaw) ?? .indoorCycle
        guard !workoutManager.isWorkoutActive else { return }
        workoutManager.startWorkout(type: workoutType, connectIfNeeded: true)
    }
}
