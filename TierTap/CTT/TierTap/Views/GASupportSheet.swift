import SwiftUI

/// Gamblers Anonymous national hotline: 1-888-GA-HELPS (1-888-242-4357).
private let gaHelplineNumber = "18882424357"
private let gaWebsiteURL = "https://www.gamblersanonymous.org/"

/// Popup shown when a downswing in session moods is detected. Offers one-tap call to Gamblers Anonymous.
struct GASupportSheet: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    var onDismiss: (() -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 28) {
                    Text("We've noticed you've had a run of tough sessions. If you need support, please call:")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if let url = URL(string: "tel:\(gaHelplineNumber)") {
                            #if os(iOS)
                            UIApplication.shared.open(url)
                            #endif
                        }
                        dismiss()
                        onDismiss?()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.fill")
                                .font(.title2)
                            Text("Call Gamblers Anonymous")
                                .font(.headline)
                            Text("(1-888-GA-HELPS)")
                                .font(.subheadline)
                                .opacity(0.9)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.white)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 24)

                    Text("24/7 • Free and confidential")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))

                    Spacer(minLength: 20)
                }
                .padding(.top, 32)
            }
            .navigationTitle("Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                        onDismiss?()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

/// Use this to open the GA website (e.g. from Settings).
struct GAWebsite {
    static var url: URL? { URL(string: gaWebsiteURL) }
}

extension Notification.Name {
    /// Posted after a session mood is saved when a downswing pattern is detected; `RootTabView` presents `GASupportSheet`.
    static let sessionMoodDownswingNeedsGASupport = Notification.Name("sessionMoodDownswingNeedsGASupport")
}

#Preview {
    GASupportSheet()
        .environmentObject(SettingsStore())
}
