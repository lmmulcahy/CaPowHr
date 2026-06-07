import WidgetKit
import SwiftUI

struct CaPowHrComplicationEntry: TimelineEntry {
    let date: Date
    let workoutTitle: String
    let workoutTypeRaw: String
}

struct CaPowHrComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaPowHrComplicationEntry {
        CaPowHrComplicationEntry(date: Date(), workoutTitle: "Start Ride", workoutTypeRaw: "indoorCycle")
    }

    func getSnapshot(in context: Context, completion: @escaping (CaPowHrComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaPowHrComplicationEntry>) -> Void) {
        let entry = currentEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }

    private func currentEntry() -> CaPowHrComplicationEntry {
        let raw = UserDefaults.standard.string(forKey: "lastWorkoutType") ?? "indoorCycle"
        let title: String
        switch raw {
        case "indoorRun": title = "Start Run"
        case "indoorWalk": title = "Start Walk"
        case "indoorRow": title = "Start Row"
        default: title = "Start Ride"
        }
        return CaPowHrComplicationEntry(date: Date(), workoutTitle: title, workoutTypeRaw: raw)
    }
}

struct CaPowHrComplicationWidgetView: View {
    var entry: CaPowHrComplicationEntry

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "bolt.heart.fill")
                .foregroundColor(.orange)
            Text(entry.workoutTitle)
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .widgetURL(URL(string: "capowhr://start?type=\(entry.workoutTypeRaw)"))
    }
}

struct CaPowHrComplicationWidget: Widget {
    let kind = "CaPowHrComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaPowHrComplicationProvider()) { entry in
            CaPowHrComplicationWidgetView(entry: entry)
        }
        .configurationDisplayName("CaPowHr")
        .description("Start your last indoor workout type.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

@main
struct CaPowHrComplicationsBundle: WidgetBundle {
    var body: some Widget {
        CaPowHrComplicationWidget()
    }
}
