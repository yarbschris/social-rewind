import RewindCore
import SwiftUI

/// Posts viewed, from on-device counts only.
struct StatsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Today") {
                ForEach(Platform.allCases.filter(\.isAvailable)) { platform in
                    LabeledContent(platform.displayName, value: "\(model.stats.count(platform: platform)) posts")
                }
            }

            Section("Last 7 days") {
                ForEach(lastSevenDays, id: \.self) { date in
                    LabeledContent(date.formatted(.dateTime.weekday(.wide).day().month()),
                                   value: "\(model.stats.total(on: date)) posts")
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("Counts stay on this iPhone and are never uploaded. A post counts once a day, after it's been at least half on screen for a second.")
            }
        }
        .navigationTitle("Stats")
    }

    private var lastSevenDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }
    }
}
