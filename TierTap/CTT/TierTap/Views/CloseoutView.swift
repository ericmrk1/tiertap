import SwiftUI
import UIKit
import Supabase

struct CloseoutView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) var dismiss
    @State private var cashOut = ""
    @State private var endingTier = ""
    @State private var showLowAlert = false
    @State private var showCelebration = false
    @State private var showEmotionPicker = false
    @State private var closedSessionId: UUID?
    @State private var privateNotes = ""

    // Session photo attachment
    @State private var sessionPhoto: UIImage?
    @State private var sessionPhotoSource: SessionPhotoSource?

    // Chip estimator entry point
    @State private var showChipEstimatorSheet = false
    @State private var chipEstimatorError: String?
    @State private var showSubscriptionPaywall = false

    var s: Session { store.liveSession ?? Session(game: "", casino: "", startTime: Date(), startingTierPoints: 0) }

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    private enum SessionPhotoSource: Identifiable {
        case camera
        case photoLibrary

        var id: Int { hashValue }
    }

    /// Quick denominations for adjusting cash-out, falling back to sensible defaults.
    private var cashOutQuickAmounts: [Int] {
        let base = settingsStore.effectiveDenominations
        return base.isEmpty ? [25, 50, 100, 200, 500, 1000] : base
    }

    var isValid: Bool {
        Int(cashOut) != nil && Int(endingTier) != nil
    }

    var previewTierEarned: Int? { Int(endingTier).map { $0 - s.startingTierPoints } }
    var previewHours: Double { s.hoursPlayed }
    var previewTPH: Double? {
        guard let e = previewTierEarned, previewHours > 0 else { return nil }
        return Double(e) / previewHours
    }
    var previewWL: Int? { Int(cashOut).map { $0 - s.totalBuyIn } }
    /// Hourly win/loss rate based on total W/L and hours played.
    /// Requires a meaningful duration so we never divide by ~0 (which happens briefly after
    /// `closeSession` clears `liveSession` and `s` falls back to a placeholder session).
    var previewHourlyWinLoss: Double? {
        guard let wl = previewWL else { return nil }
        let h = previewHours
        // At least 1 second — below that, $/hr is misleading and can overflow to infinity.
        guard h >= 1.0 / 3600.0, h.isFinite else { return nil }
        let rate = Double(wl) / h
        guard rate.isFinite else { return nil }
        return rate
    }
    /// ROI % based on initial buy-in only.
    var previewROI: Double? {
        guard let wl = previewWL,
              let initial = s.initialBuyIn, initial > 0 else { return nil }
        return (Double(wl) / Double(initial)) * 100.0
    }

    var timerStopped: Bool { s.endTime != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if showCelebration {
                    ConfettiCelebrationView()
                }
                ScrollView {
                    VStack(spacing: 12) {
                        // Top: Stop/Resume Timer primary button + compact header (one line)
                        VStack(spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                Button {
                                    if timerStopped {
                                        store.resumeLiveSessionTimer()
                                    } else {
                                        store.stopLiveSessionTimer()
                                    }
                                } label: {
                                    Label(timerStopped ? "Resume Timer" : "Stop Timer",
                                          systemImage: timerStopped ? "play.circle.fill" : "stop.circle.fill")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 20)
                                        .background(timerStopped ? Color.green : Color.red)
                                        .foregroundColor(timerStopped ? .black : .white)
                                        .cornerRadius(12)
                                }

                                if timerStopped {
                                    HStack(spacing: 16) {
                                        Button {
                                            openUberAppOrWeb()
                                        } label: {
                                            Text("🚕")
                                                .font(.system(size: 36))
                                        }
                                        .accessibilityLabel("Open Uber")

                                        Button {
                                            openOpenTableAppOrWeb()
                                        } label: {
                                            Text("🍽️")
                                                .font(.system(size: 36))
                                        }
                                        .accessibilityLabel("Open OpenTable")
                                    }
                                }
                            }

                            HStack {
                                if timerStopped {
                                    Label("Timer stopped", systemImage: "stop.circle.fill")
                                        .font(.caption).foregroundColor(.orange)
                                } else {
                                    Label("Timer running", systemImage: "play.circle.fill")
                                        .font(.caption).foregroundColor(.green)
                                }
                                Spacer()
                                Text(s.casino).font(.subheadline.bold()).foregroundColor(.white)
                                Text("·").foregroundColor(.gray)
                                Text(Session.durationString(s.duration)).font(.caption.monospacedDigit()).foregroundColor(.green)
                                Text("·").foregroundColor(.gray)
                                Text("\(settingsStore.currencySymbol)\(s.totalBuyIn)").font(.caption).foregroundColor(.gray)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(12)
                        }

                        // Inputs (compact)
                        VStack(spacing: 8) {
                            InputRow(label: "Cash Out (\(settingsStore.currencySymbol))", placeholder: "Amount leaving with", value: $cashOut)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Adjust cash out")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(cashOutQuickAmounts, id: \.self) { amt in
                                            Button("+\(settingsStore.currencySymbol)\(amt)") {
                                                let current = Int(cashOut) ?? s.totalBuyIn
                                                cashOut = String(current + amt)
                                            }
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundColor(.green)
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(cashOutQuickAmounts, id: \.self) { amt in
                                            Button("−\(settingsStore.currencySymbol)\(amt)") {
                                                let current = Int(cashOut) ?? s.totalBuyIn
                                                cashOut = String(max(0, current - amt))
                                            }
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color(.systemGray6).opacity(0.25))
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                HStack(spacing: 8) {
                                    Button("Lost everything") {
                                        cashOut = "0"
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.25))
                                    .foregroundColor(.red)
                                    .cornerRadius(8)

                                    Button("Double or nothing") {
                                        cashOut = String(s.totalBuyIn * 2)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)

                                    Button("Triple") {
                                        cashOut = String(s.totalBuyIn * 3)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                            InputRow(label: "Ending Tier Points", placeholder: "Loyalty app now", value: $endingTier)
                            if settingsStore.unitSize > 0,
                               s.totalBuyIn > settingsStore.unitSize {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.caption2)
                                    Text("Exceeds unit \(settingsStore.currencySymbol)\(settingsStore.unitSize).").font(.caption2).foregroundColor(.orange)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(6)
                            }
                        }

                        // Summary inline when valid (compact)
                        if isValid {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let wl = previewWL {
                                        Text("W/L").font(.caption2).foregroundColor(.gray)
                                        Text(wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))")
                                            .font(.subheadline.bold())
                                            .foregroundColor(wl >= 0 ? .green : .red)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Buy-in").font(.caption2).foregroundColor(.gray)
                                    Text("\(settingsStore.currencySymbol)\(s.totalBuyIn)").font(.subheadline).foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hrs").font(.caption2).foregroundColor(.gray)
                                    Text(String(format: "%.2f", previewHours)).font(.subheadline).foregroundColor(.white)
                                }
                                if let hourly = previewHourlyWinLoss,
                                   let amount = Int(exactly: round(hourly)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Hourly W/L").font(.caption2).foregroundColor(.gray)
                                        Text("\(amount >= 0 ? "+" : "-")\(settingsStore.currencySymbol)\(abs(amount))")
                                            .font(.subheadline)
                                            .foregroundColor(amount >= 0 ? .green : .red)
                                    }
                                }
                                if let roi = previewROI {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("ROI %").font(.caption2).foregroundColor(.gray)
                                        Text(String(format: "%.1f%%", roi))
                                            .font(.subheadline)
                                            .foregroundColor(roi >= 0 ? .green : .red)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(12)

                            // Removed house edge comparison since avg bet inputs are no longer collected at closeout.
                        }

                        // Private notes (local only, not shared)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Private notes (not shared)")
                                .font(.caption.bold())
                                .foregroundColor(.gray)
                            TextEditor(text: $privateNotes)
                                .frame(minHeight: 72)
                                .padding(8)
                                .background(Color(.systemGray6).opacity(0.25))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .scrollContentBackground(.hidden)
                        }

                        // Session photo attachment
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Session photo")
                                .font(.caption.bold())
                                .foregroundColor(.gray)

                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6]))
                                    .background(Color(.systemGray6).opacity(0.2))
                                    .cornerRadius(12)

                                if let image = sessionPhoto {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(10)
                                        .padding(4)
                                } else {
                                    VStack(spacing: 6) {
                                        Image(systemName: "camera.viewfinder")
                                            .font(.system(size: 24))
                                            .foregroundColor(.gray)
                                        Text("Add a photo from your session")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(16)
                                }
                            }
                            .frame(maxHeight: 220)

                            HStack(spacing: 12) {
                                Button {
                                    sessionPhotoSource = .camera
                                } label: {
                                    Label("Camera", systemImage: "camera")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.9))
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                }

                                Button {
                                    sessionPhotoSource = .photoLibrary
                                } label: {
                                    Label("Photo Library", systemImage: "photo")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6).opacity(0.35))
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                }

                                if sessionPhoto != nil {
                                    Spacer()
                                    Button(role: .destructive) {
                                        sessionPhoto = nil
                                        // Do not clear filename on live session here to avoid
                                        // edge-cases with already-closed sessions; leaving the
                                        // last saved photo is safer than dangling references.
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                            .padding(8)
                                    }
                                }
                            }
                        }

                        // Actions
                        VStack(spacing: 8) {
                            Button {
                                if let et = Int(endingTier), et < s.startingTierPoints {
                                    showLowAlert = true
                                } else { save() }
                            } label: {
                                Text("Save Session")
                                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                                    .font(.headline)
                                    .foregroundColor(isValid ? .white : .white.opacity(0.85))
                                    .background {
                                        if isValid {
                                            GameCategoryBubbleBackground(cornerRadius: 12)
                                        } else {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.gray)
                                        }
                                    }
                            }
                            .disabled(!isValid)

                            Button { dismiss() } label: {
                                Text("Cancel — Return to Session")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding()
                }
                // Floating Chip Estimator button – gated behind subscription and login
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            if hasProAccess && authStore.isSignedIn {
                                startChipEstimatorFlow()
                            } else {
                                showSubscriptionPaywall = true
                            }
                        } label: {
                            Label("Chip Estimator", systemImage: "camera.viewfinder")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.9))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .shadow(radius: 5)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
                .allowsHitTesting(true)
            }
            .navigationTitle("End Session")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Chip estimator error", isPresented: Binding<Bool>(
                get: { chipEstimatorError != nil },
                set: { if !$0 { chipEstimatorError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(chipEstimatorError ?? "Something went wrong while estimating the chip value.")
            }
            .adaptiveSheet(isPresented: $showChipEstimatorSheet) {
                ChipEstimatorSheetView(
                    sessionID: s.id,
                    game: s.game,
                    casino: s.casino,
                    cashOut: $cashOut
                )
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .environmentObject(subscriptionStore)
            }
            .alert("Tier Points Decreased", isPresented: $showLowAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Save Anyway") { save() }
            } message: {
                Text("Ending tier (\(endingTier)) is lower than starting tier (\(s.startingTierPoints)). Save anyway?")
            }
            .adaptiveSheet(isPresented: $showEmotionPicker, onDismiss: {
                if closedSessionId != nil, let co = Int(cashOut),
                   let et = Int(endingTier) {
                    let notes = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes
                    closeSessionPersistingLastGameDefaults(cashOut: co, endingTier: et, privateNotes: notes)
                    closedSessionId = nil
                    dismiss()
                }
            }) {
                SessionMoodPickerView { mood in
                    guard let co = Int(cashOut),
                          let et = Int(endingTier),
                          let id = closedSessionId else {
                        closedSessionId = nil
                        dismiss()
                        return
                    }
                    let notes = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes
                    closeSessionPersistingLastGameDefaults(cashOut: co, endingTier: et, privateNotes: notes)
                    if var session = store.sessions.first(where: { $0.id == id }) {
                        session.sessionMood = mood
                        store.updateSession(session)
                    }
                    closedSessionId = nil
                    let downswing = store.recentMoodDownswingDetected()
                    showEmotionPicker = false
                    if downswing {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NotificationCenter.default.post(name: .sessionMoodDownswingNeedsGASupport, object: nil)
                        }
                    }
                }
                .environmentObject(settingsStore)
            }
            .adaptiveSheet(item: $sessionPhotoSource) { source in
                switch source {
                case .camera:
                    #if os(iOS)
                    CameraPicker(selectedImage: .constant(nil)) { image in
                        handlePickedSessionPhoto(image)
                    }
                    #else
                    EmptyView()
                    #endif
                case .photoLibrary:
                    #if os(iOS)
                    ImagePicker(selectedImage: .constant(nil)) { image in
                        handlePickedSessionPhoto(image)
                    }
                    #else
                    EmptyView()
                    #endif
                }
            }
            .adaptiveSheet(isPresented: $showSubscriptionPaywall) {
                TierTapPaywallView()
                    .environmentObject(subscriptionStore)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
            }
        }
        .onAppear {
            privateNotes = s.privateNotes ?? ""
            if cashOut.isEmpty {
                cashOut = "\(s.totalBuyIn)"
            }
            // Default ending tier to this session's starting tier if available,
            // falling back to recent history for this casino.
            if endingTier.isEmpty {
                if s.startingTierPoints > 0 {
                    endingTier = "\(s.startingTierPoints)"
                } else if let hist = store.defaultEndingTierPoints(for: s.casino) {
                    endingTier = "\(hist)"
                } else {
                    endingTier = "0"
                }
            }

            // Load any existing session photo attached while live.
            if let fileName = s.chipEstimatorImageFilename,
               let url = ChipEstimatorPhotoStorage.url(for: fileName),
               let uiImage = UIImage(contentsOfFile: url.path) {
                sessionPhoto = uiImage
            }
        }
    }

    private func closeSessionPersistingLastGameDefaults(cashOut: Int, endingTier: Int, privateNotes: String?) {
        if let live = store.liveSession {
            settingsStore.recordLastPlayedGameChoices(from: live)
        }
        store.closeSession(cashOut: cashOut, endingTier: endingTier, privateNotes: privateNotes)
    }

    func save() {
        guard let co = Int(cashOut), let et = Int(endingTier) else { return }
        let sessionId = s.id
        let netPositive = (co - s.totalBuyIn) > 0

        let notes = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes
        if !settingsStore.promptSessionMood {
            if netPositive {
                if settingsStore.enableCasinoFeedback {
                    CelebrationPlayer.shared.celebrateWin()
                }
                showCelebration = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    closeSessionPersistingLastGameDefaults(cashOut: co, endingTier: et, privateNotes: notes)
                    dismiss()
                }
            } else {
                closeSessionPersistingLastGameDefaults(cashOut: co, endingTier: et, privateNotes: notes)
                dismiss()
            }
            return
        }

        if netPositive {
            if settingsStore.enableCasinoFeedback {
                CelebrationPlayer.shared.celebrateWin()
            }
            showCelebration = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                closedSessionId = sessionId
                showEmotionPicker = true
            }
        } else {
            closedSessionId = sessionId
            showEmotionPicker = true
        }
    }

    private func startChipEstimatorFlow() {
        guard SupabaseConfig.isConfigured else {
            chipEstimatorError = "AI is not configured for this build."
            return
        }
        showChipEstimatorSheet = true
    }

    private func handlePickedSessionPhoto(_ image: UIImage) {
        sessionPhoto = image
        if let fileName = ChipEstimatorPhotoStorage.saveImage(image, for: s.id) {
            store.setChipEstimatorImageFilename(fileName)
        }
    }

    private func openUberAppOrWeb() {
        guard let appURL = URL(string: "uber://") else { return }
        UIApplication.shared.open(appURL) { success in
            if !success, let webURL = URL(string: "https://www.uber.com/") {
                UIApplication.shared.open(webURL)
            }
        }
    }

    private func openOpenTableAppOrWeb() {
        guard let appURL = URL(string: "opentable://") else { return }
        UIApplication.shared.open(appURL) { success in
            if !success, let webURL = URL(string: "https://www.opentable.com") {
                UIApplication.shared.open(webURL)
            }
        }
    }
}

struct ChipEstimatorSheetView: View {
    let sessionID: UUID
    let game: String
    let casino: String
    @Binding var cashOut: String

    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedImage: UIImage?
    @State private var isEstimating = false
    @State private var estimatedAmount: Int?
    @State private var errorMessage: String?

    private enum ChipPhotoSource: Identifiable {
        case camera
        case photoLibrary

        var id: Int { hashValue }
    }

    @State private var chipPhotoSource: ChipPhotoSource?

    private var canEstimate: Bool {
        selectedImage != nil &&
        !isEstimating &&
        SupabaseConfig.isConfigured &&
        authStore.isSignedIn &&
        (subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive || settingsStore.canUseAI())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [settingsStore.secondaryColor, settingsStore.primaryColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 6) {
                            Text(casino.isEmpty ? "Unknown casino" : casino)
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            Text(game.isEmpty ? "Unknown table game" : game)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Text("Chip Estimator")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6).opacity(0.18))
                        .cornerRadius(16)

                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6]))
                                    .background(Color(.systemGray6).opacity(0.15))
                                    .cornerRadius(16)

                                if let image = selectedImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(14)
                                        .padding(4)
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "camera.viewfinder")
                                            .font(.system(size: 32))
                                            .foregroundColor(.gray)
                                        Text("Add a photo of your chips")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(24)
                                }
                            }
                            .frame(maxHeight: 280)

                            HStack(spacing: 12) {
                                Button {
                                    chipPhotoSource = .camera
                                } label: {
                                    Label("Camera", systemImage: "camera")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.blue.opacity(0.95))
                                        .foregroundColor(.white)
                                        .cornerRadius(18)
                                }

                                Button {
                                    chipPhotoSource = .photoLibrary
                                } label: {
                                    Label("Photo Library", systemImage: "photo")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color(.systemGray6).opacity(0.35))
                                        .foregroundColor(.white)
                                        .cornerRadius(18)
                                }
                            }

                            Button {
                                Task { await estimateAmount() }
                            } label: {
                                HStack {
                                    if isEstimating {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(isEstimating ? "Estimating…" : "Estimate with AI")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(canEstimate ? Color.green : Color.gray)
                                .foregroundColor(canEstimate ? .black : .white)
                                .cornerRadius(16)
                            }
                            .disabled(!canEstimate)

                            if let estimatedAmount {
                                VStack(spacing: 8) {
                                    Text("Estimated value")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text("\(settingsStore.currencySymbol)\(estimatedAmount)")
                                        .font(.title.bold())
                                        .foregroundColor(.green)

                                    Button {
                                        cashOut = String(estimatedAmount)
                                        dismiss()
                                    } label: {
                                        Text("Use as cash-out amount")
                                            .font(.subheadline.bold())
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(Color.blue.opacity(0.95))
                                            .foregroundColor(.white)
                                            .cornerRadius(18)
                                    }
                                }
                                .padding(.top, 8)
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding()
                }

                if isEstimating {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 14) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .green))
                                    .scaleEffect(1.3)
                                Text("Estimating chip value…")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Analyzing your photo with TierTap AI.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(20)
                            .background(Color(.systemGray6).opacity(0.95))
                            .cornerRadius(18)
                        }
                }
            }
            .navigationTitle("Chip Estimator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.green)
                }
            }
            .adaptiveSheet(item: $chipPhotoSource) { source in
                switch source {
                case .camera:
                    #if os(iOS)
                    CameraPicker(selectedImage: .constant(nil)) { image in
                        selectedImage = image
                    }
                    #else
                    EmptyView()
                    #endif
                case .photoLibrary:
                    #if os(iOS)
                    ImagePicker(selectedImage: .constant(nil)) { image in
                        selectedImage = image
                    }
                    #else
                    EmptyView()
                    #endif
                }
            }
        }
    }

    // MARK: - Estimation

    private func estimateAmount() async {
        guard let image = selectedImage else {
            await MainActor.run { errorMessage = "Please add a photo first." }
            return
        }
        guard SupabaseConfig.isConfigured, let client = supabase else {
            await MainActor.run { errorMessage = "AI is not configured for this build." }
            return
        }
        guard authStore.isSignedIn else {
            await MainActor.run { errorMessage = "Chip Estimator is only available to signed-in users." }
            return
        }
        if !subscriptionStore.isPro && !settingsStore.isSubscriptionOverrideActive && !settingsStore.canUseAI() {
            await MainActor.run { errorMessage = "You've reached today's free AI limit. Try again tomorrow." }
            return
        }

        await MainActor.run {
            isEstimating = true
            errorMessage = nil
            estimatedAmount = nil
        }

        struct GeminiInlineData: Encodable {
            let mime_type: String
            let data: String

            enum CodingKeys: String, CodingKey {
                case mime_type = "mime_type"
                case data
            }
        }

        struct GeminiPartImage: Encodable {
            let text: String?
            let inline_data: GeminiInlineData?

            enum CodingKeys: String, CodingKey {
                case text
                case inline_data = "inline_data"
            }
        }

        struct GeminiContentImage: Encodable {
            let role: String
            let parts: [GeminiPartImage]
        }

        struct GeminiImageRequest: Encodable {
            let contents: [GeminiContentImage]
        }

        struct GeminiPart: Decodable {
            let text: String?
        }

        struct GeminiContent: Decodable {
            let parts: [GeminiPart]?
        }

        struct GeminiCandidate: Decodable {
            let content: GeminiContent?
        }

        struct GeminiRouterResponse: Decodable {
            let candidates: [GeminiCandidate]?
        }

        guard let imageData = image.jpegData(compressionQuality: 0.9)?.base64EncodedString() else {
            await MainActor.run {
                isEstimating = false
                errorMessage = "Unable to process image."
            }
            return
        }

        let gameText = game.isEmpty ? "an unknown table game" : game
        let casinoText = casino.isEmpty ? "an unknown casino" : casino

        let prompt = """
        You are estimating the total cash value of casino chips shown in this photo.
        The game is \(gameText) and the location is \(casinoText).

        Only estimate a value if the primary subject of the photo is CLEARLY casino chips, cash, or other casino items that have an obvious, standard cash-equivalent value (for example, chips, plaques, or bills).
        If the photo does not clearly show casino chips, cash, or obvious casino items of monetary value, or if you are not confident it is a casino chip/cash photo, you MUST respond with the single word UNKNOWN.

        If it IS a valid casino chip/cash photo, respond with only a single integer number of dollars (no currency symbol, commas, or extra text).
        Do not explain your reasoning; just return either UNKNOWN or a single integer.
        """

        let body = GeminiImageRequest(
            contents: [
                .init(
                    role: "user",
                    parts: [
                        .init(text: prompt, inline_data: nil),
                        .init(
                            text: nil,
                            inline_data: GeminiInlineData(
                                mime_type: "image/jpeg",
                                data: imageData
                            )
                        )
                    ]
                )
            ]
        )

        do {
            if !subscriptionStore.isPro && !settingsStore.isSubscriptionOverrideActive {
                await MainActor.run {
                    settingsStore.registerAICall()
                }
            }

            let response: GeminiRouterResponse = try await GeminiRouterThrottle.shared.executeWithRetries {
                try await client.functions.invoke(
                    "gemini-router",
                    options: FunctionInvokeOptions(body: body)
                )
            }
            let text = response.candidates?
                .first?
                .content?
                .parts?
                .compactMap { $0.text }
                .joined(separator: "\n") ?? ""
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            // If the model indicates it cannot confidently estimate a chip/cash value.
            if trimmedText == "UNKNOWN" {
                await MainActor.run {
                    isEstimating = false
                    errorMessage = "AI could not identify a clear chip or cash value from this photo. Make sure the image shows casino chips or cash clearly."
                }
                return
            }

            let digits = text.compactMap { $0.isNumber ? $0 : nil }
            let amount = Int(String(digits))

            await MainActor.run {
                isEstimating = false
                if let amount {
                    estimatedAmount = amount

                    if let fileName = ChipEstimatorPhotoStorage.saveImage(image, for: sessionID) {
                        store.setChipEstimatorImageFilename(fileName)
                    }
                } else {
                    errorMessage = "AI did not return a clear numeric estimate."
                }
            }
        } catch {
            await MainActor.run {
                isEstimating = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

