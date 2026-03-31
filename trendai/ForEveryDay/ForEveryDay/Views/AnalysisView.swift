import SwiftUI

struct AnalysisView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Analysis",
                systemImage: "sparkles",
                description: Text("This space will use on-device or cloud AI in a future update to interpret your streaks, slip-ups, and patterns.")
            )
            .navigationTitle("Analysis")
        }
    }
}
