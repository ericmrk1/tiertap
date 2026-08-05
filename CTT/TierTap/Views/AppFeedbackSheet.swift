import StoreKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

    /// Copies a random positive review suggestion so the user can paste it on the App Store form.
    /// Apple does not allow pre-filling review text via URL; pasteboard is the supported path.
    @discardableResult
    static func copyRandomPositiveReviewComment() -> String {
        let comment = AppStoreReviewComments.randomComment()
        #if os(iOS)
        UIPasteboard.general.string = comment
        #endif
        return comment
    }
}

/// Bottom sheet: “We Appreciate Your Feedback” + 5 stars.
struct AppFeedbackSheet: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @State private var selectedRating: Int = 0
    @State private var didSubmit = false
    @State private var preparedReviewComment: String?

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
                    } else if didSubmit, let preparedReviewComment {
                        VStack(spacing: 12) {
                            L10nText("Review text copied — paste it in the App Store.")
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white.opacity(0.95))
                                .padding(.horizontal, 24)

                            Text(preparedReviewComment)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 28)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
            // Prefill path: random positive comment → pasteboard (App Store form can’t be URL-filled).
            preparedReviewComment = AppStoreReview.copyRandomPositiveReviewComment()
            requestReview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
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
