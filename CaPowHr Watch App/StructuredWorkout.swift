import Foundation

enum StructuredWorkoutTemplate: String, CaseIterable, Identifiable {
    case free
    case warmupWorkCooldown
    case intervals4x4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: return "Free Workout"
        case .warmupWorkCooldown: return "Warm / Work / Cool"
        case .intervals4x4: return "4×4 Intervals"
        }
    }
}

struct StructuredWorkoutPhase: Identifiable {
    let id = UUID()
    let name: String
    let durationSeconds: TimeInterval
}

struct StructuredWorkoutPlan {
    let template: StructuredWorkoutTemplate
    let phases: [StructuredWorkoutPhase]

    static func plan(for template: StructuredWorkoutTemplate) -> StructuredWorkoutPlan {
        switch template {
        case .free:
            return StructuredWorkoutPlan(template: template, phases: [])
        case .warmupWorkCooldown:
            return StructuredWorkoutPlan(
                template: template,
                phases: [
                    StructuredWorkoutPhase(name: "Warmup", durationSeconds: 5 * 60),
                    StructuredWorkoutPhase(name: "Work", durationSeconds: 20 * 60),
                    StructuredWorkoutPhase(name: "Cooldown", durationSeconds: 5 * 60)
                ]
            )
        case .intervals4x4:
            var phases: [StructuredWorkoutPhase] = [
                StructuredWorkoutPhase(name: "Warmup", durationSeconds: 10 * 60)
            ]
            for i in 1...4 {
                phases.append(StructuredWorkoutPhase(name: "Work \(i)", durationSeconds: 4 * 60))
                phases.append(StructuredWorkoutPhase(name: "Rest \(i)", durationSeconds: 3 * 60))
            }
            phases.append(StructuredWorkoutPhase(name: "Cooldown", durationSeconds: 5 * 60))
            return StructuredWorkoutPlan(template: template, phases: phases)
        }
    }
}

final class StructuredWorkoutController: ObservableObject {
    @Published private(set) var activePlan: StructuredWorkoutPlan?
    @Published private(set) var phaseIndex: Int = 0
    @Published private(set) var phaseElapsedSeconds: TimeInterval = 0
    @Published private(set) var isComplete: Bool = false

    var currentPhase: StructuredWorkoutPhase? {
        guard let plan = activePlan, phaseIndex < plan.phases.count else { return nil }
        return plan.phases[phaseIndex]
    }

    var currentPhaseRemainingSeconds: TimeInterval {
        guard let phase = currentPhase else { return 0 }
        return max(0, phase.durationSeconds - phaseElapsedSeconds)
    }

    func start(template: StructuredWorkoutTemplate) {
        let plan = StructuredWorkoutPlan.plan(for: template)
        activePlan = plan.phases.isEmpty ? nil : plan
        phaseIndex = 0
        phaseElapsedSeconds = 0
        isComplete = plan.phases.isEmpty
    }

    func reset() {
        activePlan = nil
        phaseIndex = 0
        phaseElapsedSeconds = 0
        isComplete = false
    }

    func tick() {
        guard let phase = currentPhase else { return }
        phaseElapsedSeconds += 1
        if phaseElapsedSeconds >= phase.durationSeconds {
            advancePhase()
        }
    }

    private func advancePhase() {
        guard let plan = activePlan else { return }
        if phaseIndex + 1 >= plan.phases.count {
            isComplete = true
            return
        }
        phaseIndex += 1
        phaseElapsedSeconds = 0
    }
}
