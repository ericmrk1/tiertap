import StoreKit
import SwiftUI

/// App Store numeric ID (App Store Connect).
private let tierTapAppStoreID = "6760150454"

enum AppStoreReview {
    static var writeReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(tierTapAppStoreID)?action=write-review")!
    }

    /// Opens the App Store write-review page (reliable path for Settings-initiated reviews).
    static func openWriteReviewPage() {
        #if os(iOS)
        UIApplication.shared.open(writeReviewURL)
        #endif
    }
}

/// Bottom sheet: “We Appreciate Your Feedback” + 5 stars.
struct AppFeedbackSheet: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @State private var selectedRating: Int = 0
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()

                VStack(spacing: 28) {
                    L10nText("We Appreciate Your Feedback")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)

                    if didSubmit && selectedRating < 4 {
                        L10nText("Thank you — we read every bit of feedback.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 24)
                    } else {
                        HStack(spacing: 14) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    handleRating(star)
                                } label: {
                                    Image(systemName: star <= selectedRating ? "star.fill" : "star")
                                        .font(.system(size: 36, weight: .semibold))
                                        .foregroundColor(star <= selectedRating ? .yellow : .white.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .disabled(didSubmit)
                                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 12)
                }
                .padding(.top, 36)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private func handleRating(_ rating: Int) {
        guard !didSubmit else { return }
        selectedRating = rating
        didSubmit = true
        settingsStore.markAppFeedbackSubmitted()

        if rating >= 4 {
            // Hybrid 1+2: native in-app review prompt, then App Store write-review URL.
            requestReview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                dismiss()
                AppStoreReview.openWriteReviewPage()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                dismiss()
            }
        }
    }
}

extension Notification.Name {
    /// Posted when a play session becomes `.complete` (live close-out, past add, or incomplete → complete).
    static let tierTapSessionCompletedForReviewPrompt = Notification.Name("tierTapSessionCompletedForReviewPrompt")
}
