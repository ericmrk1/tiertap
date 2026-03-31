import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("App", value: "For Every Day")
                    LabeledContent("Version", value: "1.0")
                }
                Section {
                    Text("Notifications, appearance, data export, and more will land here.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Coming soon")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
