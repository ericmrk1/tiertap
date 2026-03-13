import SwiftUI
import UIKit

/// Fill in missing closeout details for a session that was cashed out from Watch (requiring more info).
struct CompleteSessionView: View {
    let session: Session
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var cashOut: String = ""
    @State private var avgBetActual = ""
    @State private var avgBetRated = ""
    @State private var endingTier = ""
    @State private var showLowAlert = false
    @State private var showCelebration = false
    @State private var showEmotionPicker = false
    @State private var completedSessionId: UUID?
    @State private var showGASheet = false
    @State private var privateNotes = ""
    @State private var chipEstimatorImageFilename: String?
    @State private var chipPreviewImage: UIImage?
    @State private var showChipSourceDialog = false

    private enum ChipPhotoSource: Identifiable {
        case camera
        case photoLibrary

        var id: Int { hashValue }
    }

    @State private var chipPhotoSource: ChipPhotoSource?

    init(session: Session) {
        self.session = session
    }

    var isValid: Bool {
        Int(cashOut) != nil && Int(avgBetActual) != nil &&
        Int(avgBetRated) != nil && Int(endingTier) != nil
    }

    var previewTierEarned: Int? { Int(endingTier).map { $0 - session.startingTierPoints } }
    var previewHours: Double { session.hoursPlayed }
    var previewTPH: Double? {
        guard let e = previewTierEarned, previewHours > 0 else { return nil }
        return Double(e) / previewHours
    }
    var previewWL: Int? { Int(cashOut).map { $0 - session.totalBuyIn } }
    var previewT100: Double? {
        guard let r = Int(avgBetRated), r >= 100,
              let e = previewTierEarned, previewHours > 0 else { return nil }
        return (Double(e) / (Double(r) * previewHours)) * 100
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if showCelebration {
                    ConfettiCelebrationView()
                }
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 6) {
                            Text(session.casino).font(.title2.bold()).foregroundColor(.white)
                            Text(session.game).foregroundColor(.gray)
                            HStack(spacing: 16) {
                                Label(Session.durationString(session.duration), systemImage: "clock")
                                Label("Buy-in: \(settingsStore.currencySymbol)\(session.totalBuyIn)", systemImage: "dollarsign.circle")
                            }
                            .font(.caption).foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        VStack(spacing: 14) {
                            InputRow(label: "Cash Out (\(settingsStore.currencySymbol))", placeholder: "Amount left with", value: $cashOut)
                            InputRow(label: "Avg Bet Actual (\(settingsStore.currencySymbol))", placeholder: "Actual avg bet", value: $avgBetActual)
                            InputRow(label: "Avg Bet Rated (\(settingsStore.currencySymbol))", placeholder: "Rated avg bet", value: $avgBetRated)
                            InputRow(label: "Ending Tier Points", placeholder: "From loyalty app", value: $endingTier)
                            if settingsStore.unitSize > 0,
                               (Int(avgBetActual) ?? 0) > settingsStore.unitSize || (Int(avgBetRated) ?? 0) > settingsStore.unitSize || session.totalBuyIn > settingsStore.unitSize {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Bet or buy-in exceeds unit size (\(settingsStore.currencySymbol)\(settingsStore.unitSize)).")
                                        .font(.caption).foregroundColor(.orange)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(8)
                            }
                        }

                        if isValid {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Session Summary").font(.headline).foregroundColor(.white)
                                Divider().background(Color.gray.opacity(0.3))
                                if let wl = previewWL {
                                    SummaryRow(label: "Win/Loss",
                                               value: wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))",
                                               color: wl >= 0 ? .green : .red)
                                }
                                SummaryRow(label: "Total Buy-In", value: "\(settingsStore.currencySymbol)\(session.totalBuyIn)", color: .white)
                                SummaryRow(label: "Hours Played", value: String(format: "%.2f", previewHours), color: .white)
                                if let e = previewTierEarned {
                                    SummaryRow(label: "Tier Points Earned",
                                               value: "\(e >= 0 ? "+" : "")\(e)",
                                               color: e >= 0 ? .green : .orange)
                                }
                                if let t = previewTPH {
                                    SummaryRow(label: "Tiers / Hour", value: String(format: "%.1f", t), color: .white)
                                }
                                if let t100 = previewT100 {
                                    SummaryRow(label: "Tiers per 100 \(settingsStore.currencySymbol) Rated Bet-Hour",
                                               value: String(format: "%.2f", t100), color: .white)
                                }
                                if let wl = previewWL,
                                   let abet = Int(avgBetActual), abet > 0,
                                   let result = StrategyDatabase.expectedLossAndAboveEdge(gameName: session.game, winLoss: wl, avgBet: abet, hours: previewHours) {
                                    let above = result.aboveEdge >= 0
                                    let amount = Int(round(abs(result.aboveEdge)))
                                    SummaryRow(label: "Vs house edge",
                                               value: above ? "\(settingsStore.currencySymbol)\(amount) above" : "\(settingsStore.currencySymbol)\(amount) below",
                                               color: above ? .green : .orange)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(16)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Private notes (not shared)")
                                .font(.caption.bold())
                                .foregroundColor(.gray)
                            TextEditor(text: $privateNotes)
                                .frame(minHeight: 72)
                                .padding(8)
                                .background(Color(.systemGray6).opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .scrollContentBackground(.hidden)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "camera.viewfinder")
                                    .foregroundColor(.green)
                                Text("Chip photo (optional)")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                            }
                            if let image = chipPreviewImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            HStack {
                                Button {
                                    showChipSourceDialog = true
                                } label: {
                                    Label(
                                        chipPreviewImage == nil ? "Add chip photo" : "Replace chip photo",
                                        systemImage: "camera"
                                    )
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.9))
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                }
                                if chipPreviewImage != nil {
                                    Button(role: .destructive) {
                                        chipPreviewImage = nil
                                        chipEstimatorImageFilename = nil
                                        // Persist removal immediately.
                                        var updated = session
                                        updated.chipEstimatorImageFilename = nil
                                        store.updateSession(updated)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .padding(8)
                                            .background(Color.red.opacity(0.9))
                                            .foregroundColor(.white)
                                            .clipShape(Circle())
                                    }
                                }
                            }
                        }

                        VStack(spacing: 10) {
                            Button {
                                if let et = Int(endingTier), et < session.startingTierPoints {
                                    showLowAlert = true
                                } else { save() }
                            } label: {
                                Text("Save as Complete")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(isValid ? Color.green : Color.gray)
                                    .foregroundColor(isValid ? .black : .white)
                                    .cornerRadius(14).font(.headline)
                            }
                            .disabled(!isValid)

                            Button { dismiss() } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color(.systemGray6).opacity(0.2))
                                    .foregroundColor(.white).cornerRadius(14)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Complete Session")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                privateNotes = session.privateNotes ?? ""
                cashOut = session.cashOut.map { "\($0)" } ?? ""
                chipEstimatorImageFilename = session.chipEstimatorImageFilename
                if let fileName = session.chipEstimatorImageFilename,
                   let url = ChipEstimatorPhotoStorage.url(for: fileName),
                   let uiImage = UIImage(contentsOfFile: url.path) {
                    chipPreviewImage = uiImage
                } else {
                    chipPreviewImage = nil
                }
                // Default ending tier to this session's starting/ending tier if available,
                // falling back to recent history for this casino.
                if endingTier.isEmpty {
                    if let et = session.endingTierPoints {
                        endingTier = "\(et)"
                    } else if session.startingTierPoints > 0 {
                        endingTier = "\(session.startingTierPoints)"
                    } else if let hist = store.defaultEndingTierPoints(for: session.casino) {
                        endingTier = "\(hist)"
                    } else {
                        endingTier = "0"
                    }
                }
                // Pre-populate avg bets based on recent history for this game if missing.
                if avgBetActual.isEmpty || avgBetRated.isEmpty {
                    let defaults = store.defaultAvgBets(for: session.game)
                    if avgBetActual.isEmpty, let a = defaults.actual {
                        avgBetActual = "\(a)"
                    }
                    if avgBetRated.isEmpty, let r = defaults.rated {
                        avgBetRated = "\(r)"
                    }
                }
            }
            .alert("Tier Points Decreased", isPresented: $showLowAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Save Anyway") { save() }
            } message: {
                Text("Ending tier (\(endingTier)) is lower than starting tier (\(session.startingTierPoints)). Save anyway?")
            }
            .adaptiveSheet(isPresented: $showEmotionPicker, onDismiss: {
                if completedSessionId == session.id, let co = Int(cashOut), let aba = Int(avgBetActual),
                   let abr = Int(avgBetRated), let et = Int(endingTier) {
                    var updated = session
                    updated.cashOut = co
                    updated.avgBetActual = aba
                    updated.avgBetRated = abr
                    updated.endingTierPoints = et
                    updated.status = .complete
                    updated.privateNotes = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes
                    store.updateSession(updated)
                    completedSessionId = nil
                    dismiss()
                }
            }) {
                SessionMoodPickerView { mood in
                    guard completedSessionId == session.id,
                          let co = Int(cashOut), let aba = Int(avgBetActual),
                          let abr = Int(avgBetRated), let et = Int(endingTier) else {
                        completedSessionId = nil
                        dismiss()
                        return
                    }
                    var updated = session
                    updated.cashOut = co
                    updated.avgBetActual = aba
                    updated.avgBetRated = abr
                    updated.endingTierPoints = et
                    updated.status = .complete
                    updated.sessionMood = mood
                    updated.privateNotes = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes
                    store.updateSession(updated)
                    completedSessionId = nil
                    if store.recentMoodDownswingDetected() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showGASheet = true
                        }
                    }
                    dismiss()
                }
                .environmentObject(settingsStore)
            }
            .adaptiveSheet(isPresented: $showGASheet) {
                GASupportSheet(onDismiss: {
                    showGASheet = false
                    dismiss()
                })
                .environmentObject(settingsStore)
            }
            .confirmationDialog(
                "Choose a photo source",
                isPresented: $showChipSourceDialog,
                titleVisibility: .visible
            ) {
                Button("Camera") {
                    chipPhotoSource = .camera
                }
                Button("Photo Library") {
                    chipPhotoSource = .photoLibrary
                }
                Button("Cancel", role: .cancel) {}
            }
            .adaptiveSheet(item: $chipPhotoSource) { source in
                switch source {
                case .camera:
                    #if os(iOS)
                    CameraPicker(selectedImage: .constant(nil)) { image in
                        handleChipPhotoChange(image)
                    }
                    #else
                    EmptyView()
                    #endif
                case .photoLibrary:
                    #if os(iOS)
                    ImagePicker(selectedImage: .constant(nil)) { image in
                        handleChipPhotoChange(image)
                    }
                    #else
                    EmptyView()
                    #endif
                }
            }
        }
    }

    func save() {
        guard let co = Int(cashOut), let aba = Int(avgBetActual),
              let abr = Int(avgBetRated), let et = Int(endingTier) else { return }
        let netPositive = (co - session.totalBuyIn) > 0

        if !settingsStore.promptSessionMood {
            var updated = session
            updated.cashOut = co
            updated.avgBetActual = aba
            updated.avgBetRated = abr
            updated.endingTierPoints = et
            updated.status = .complete
            updated.privateNotes = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes
            updated.chipEstimatorImageFilename = chipEstimatorImageFilename
            store.updateSession(updated)
            if netPositive {
                if settingsStore.enableCasinoFeedback {
                    CelebrationPlayer.shared.celebrateWin()
                }
                showCelebration = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { dismiss() }
            } else {
                dismiss()
            }
            return
        }

        completedSessionId = session.id
        if netPositive {
            if settingsStore.enableCasinoFeedback {
                CelebrationPlayer.shared.celebrateWin()
            }
            showCelebration = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                showEmotionPicker = true
            }
        } else {
            showEmotionPicker = true
        }
    }

    private func handleChipPhotoChange(_ image: UIImage) {
        if let fileName = ChipEstimatorPhotoStorage.saveImage(image, for: session.id) {
            chipEstimatorImageFilename = fileName
            chipPreviewImage = image
            var updated = session
            updated.chipEstimatorImageFilename = fileName
            store.updateSession(updated)
        }
    }
}
