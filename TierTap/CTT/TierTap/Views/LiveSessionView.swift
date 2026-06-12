import SwiftUI

struct LiveSessionView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var rewardWalletStore: RewardWalletStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var elapsed: TimeInterval = 0
    @State private var showBuyInSheet = false
    @State private var showFreePlaySheet = false
    @State private var showUpdateStackSheet = false
    @State private var showCompSheet = false
    @State private var showCloseout = false
    @State private var showStrategyOdds = false
    @State private var showPrivateNotes = false
    @State private var showMissingInfoAlert = false
    #if os(iOS)
    @State private var liveSessionShareRef: PostCloseoutSessionRef?
    @State private var showSessionPhotos = false
    #endif

    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Required fields that must be set before closing out. Returns list of missing item names.
    private var missingInfoFields: [String] {
        var missing: [String] = []
        if s.game.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Game") }
        if s.casino.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Casino / Location") }
        if s.totalBuyIn == 0 && s.totalFreePlay == 0 {
            missing.append("Buy-in or free play")
        }
        return missing
    }

    private var hasMissingInfo: Bool { !missingInfoFields.isEmpty }

    /// Quick-add buy-in denominations for the live buy-in sheet.
    private var quickBuyIns: [Int] {
        [50, 100, 200, 500, 1_000, 5_000, 10_000, 20_000, 50_000, 100_000]
    }

    var s: Session { store.liveSession ?? Session(game: "", casino: "", startTime: Date(), startingTierPoints: 0) }

    private var isSlotsSession: Bool { s.isSlotsSession }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Timer Hero
                    VStack(spacing: 6) {
                        HStack {
                            HStack(spacing: 5) {
                                Circle().fill(Color.red).frame(width: 7, height: 7)
                                L10nText("LIVE").font(.caption.bold()).foregroundColor(.red)
                            }
                            Spacer()
                            Text("Started \(s.startTime, style: .time)")
                                .font(.caption).foregroundColor(.gray)
                        }
                        Text(s.casino).font(.title2.bold()).foregroundColor(.white)
                        Text(s.game).font(.subheadline).foregroundColor(.gray)
                        Text(Session.durationString(elapsed))
                            .font(.system(size: 60, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.vertical, 4)

                        if isSlotsSession {
                            VStack(spacing: 4) {
                                Text("\(settingsStore.currencySymbol)\(s.totalBuyIn.formatted(.number.grouping(.automatic)))")
                                    .font(.system(size: 52, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                L10nText("Total buy-in")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .padding(.top, 2)
                            .padding(.bottom, 6)
                            .accessibilityLabel("Total buy-in \(settingsStore.currencySymbol)\(s.totalBuyIn.formatted(.number.grouping(.automatic)))")
                        } else {
                            Button {
                                showUpdateStackSheet = true
                            } label: {
                                Text("\(settingsStore.currencySymbol)\(s.resolvedLiveStackAmount.formatted(.number.grouping(.automatic)))")
                                    .font(.system(size: 52, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 14)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.68))
                                    )
                                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                            .padding(.bottom, 6)
                            .accessibilityLabel("Stack \(settingsStore.currencySymbol)\(s.resolvedLiveStackAmount.formatted(.number.grouping(.automatic))). Tap to update.")
                        }

                        HStack(spacing: 10) {
                            
                                Button { showPrivateNotes = true } label: {
                                    Image(systemName: "note.text")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.green)
                                        .frame(width: 44, height: 36)
                                        .background(Color(.systemGray6).opacity(0.25))
                                        .cornerRadius(10)
                                }
                                .accessibilityLabel("Private notes")

                                Button { showStrategyOdds = true } label: {
                                    L10nText("Info")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6).opacity(0.25))
                                        .cornerRadius(10)
                                }
                            #if os(iOS)
                                Button {
                                    liveSessionShareRef = PostCloseoutSessionRef(id: s.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.subheadline.weight(.medium))
                                        L10nText("Share")
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .cornerRadius(10)
                                }
                                .accessibilityLabel("Share session")

                                SessionPhotosEntryButton {
                                    showSessionPhotos = true
                                }
                            #endif
                            
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6).opacity(0.12))

                    ScrollView {
                        VStack(spacing: 16) {
                            // Buy-In Panel
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    L10nText("Buy-Ins").font(.headline).foregroundColor(.white)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text("Total: \(settingsStore.currencySymbol)\(s.totalBuyIn)")
                                            .font(.title3.bold())
                                            .foregroundColor(.white)
                                        if let rate = s.liveSessionWinRatePerHour {
                                            let rSign = rate > 0 ? "+" : (rate < 0 ? "-" : "")
                                            let rMag = abs(rate.rounded())
                                            Text("\(rSign)\(settingsStore.currencySymbol)\(Int(rMag).formatted(.number.grouping(.automatic)))/hr")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                                ForEach(s.buyInEvents) { ev in
                                    HStack {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .foregroundColor(.green).font(.caption)
                                        Text("\(settingsStore.currencySymbol)\(ev.amount)").foregroundColor(.white)
                                        Spacer()
                                        Text(ev.timestamp, style: .time)
                                            .font(.caption).foregroundColor(.gray)
                                    }
                                }
                                if s.totalFreePlay > 0 {
                                    HStack {
                                        L10nText("Free play")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        Spacer()
                                        Text("\(settingsStore.currencySymbol)\(s.totalFreePlay)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.green)
                                    }
                                    ForEach(s.freePlayEvents) { ev in
                                        HStack {
                                            Image(systemName: "ticket.fill")
                                                .foregroundColor(.green).font(.caption)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(settingsStore.currencySymbol)\(ev.amount)")
                                                    .foregroundColor(.white)
                                                Text(ev.playTypeDisplayLabel)
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                            Spacer()
                                            Text(ev.timestamp, style: .time)
                                                .font(.caption).foregroundColor(.gray)
                                        }
                                    }
                                }
                                VStack(spacing: 10) {
                                    HStack(spacing: 12) {
                                        Button {
                                            showCompSheet = true
                                        } label: {
                                            LocalizedLabel(title: "Comp", systemImage: "gift.fill")
                                                .font(.headline)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 14)
                                                .padding(.horizontal)
                                                .background(Color(.systemGray6).opacity(0.25))
                                                .foregroundColor(.green)
                                                .cornerRadius(14)
                                        }
                                        Button {
                                            showBuyInSheet = true
                                        } label: {
                                            LocalizedLabel(title: "Buy-In", systemImage: "plus.circle")
                                                .font(.headline)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 14)
                                                .padding(.horizontal)
                                                .background(Color(.systemGray6).opacity(0.25))
                                                .foregroundColor(.green)
                                                .cornerRadius(14)
                                        }
                                    }
                                    Button {
                                        showFreePlaySheet = true
                                    } label: {
                                        LocalizedLabel(title: "Free Play", systemImage: "ticket.fill")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .padding(.horizontal)
                                            .background(Color(.systemGray6).opacity(0.25))
                                            .foregroundColor(.green)
                                            .cornerRadius(14)
                                    }
                                    if !isSlotsSession {
                                        Button {
                                            showUpdateStackSheet = true
                                        } label: {
                                            LocalizedChipStackLabel(
                                                title: "Stack: \(settingsStore.currencySymbol)\(s.resolvedLiveStackAmount.formatted(.number.grouping(.automatic)))"
                                            )
                                                .font(.headline)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 14)
                                                .padding(.horizontal)
                                                .background(Color(.systemGray6).opacity(0.25))
                                                .foregroundColor(.green)
                                                .cornerRadius(14)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(16)

                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    L10nText("Comps").font(.headline).foregroundColor(.white)
                                    Spacer()
                                    Text("Total: \(settingsStore.currencySymbol)\(s.totalComp)")
                                        .font(.title3.bold()).foregroundColor(.white)
                                }
                                if s.compEvents.isEmpty {
                                    L10nText("No comps logged yet.")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                } else {
                                    ForEach(s.compEvents) { ev in
                                        HStack(alignment: .firstTextBaseline) {
                                            Image(systemName: ev.kind.symbolName)
                                                .foregroundColor(.green).font(.caption)
                                            CompEventPhotoThumbnail(compEventID: ev.id, side: 40)
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(ev.kind.title)
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                    if let fbLine = ev.foodBeverageKindDisplayLabel {
                                                        Text("· \(fbLine)")
                                                            .font(.caption)
                                                            .foregroundColor(.green)
                                                    }
                                                    Text("\(settingsStore.currencySymbol)\(ev.amount)")
                                                        .foregroundColor(.white)
                                                }
                                                if let d = ev.details, !d.isEmpty {
                                                    Text(d)
                                                        .font(.caption2)
                                                        .foregroundColor(.gray)
                                                        .lineLimit(2)
                                                }
                                            }
                                            Spacer()
                                            Text(ev.timestamp, style: .time)
                                                .font(.caption).foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(16)

                            Button {
                                if hasMissingInfo {
                                    showMissingInfoAlert = true
                                } else {
                                    if let live = store.liveSession {
                                        settingsStore.recordLastPlayedGameChoices(from: live)
                                    }
                                    store.fastCloseSessionWithDefaultsUnverified()
                                }
                            } label: {
                                Group {
                                    if isSlotsSession {
                                        LocalizedFastCloseOutLabel()
                                    } else {
                                        LocalizedLabel(title: "Fast Close Out", systemImage: "bolt.fill")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .padding(.horizontal, 16)
                                .background(isSlotsSession ? Color(.systemGray6).opacity(0.25) : Color.orange.opacity(0.9))
                                .foregroundColor(isSlotsSession ? .green : .white)
                                .cornerRadius(14)
                                .font(.headline)
                            }

                            Button {
                                if hasMissingInfo {
                                    showMissingInfoAlert = true
                                } else {
                                    if settingsStore.enableCasinoFeedback {
                                        CelebrationPlayer.shared.playQuickChime()
                                    }
                                    showCloseout = true
                                }
                            } label: {
                                LocalizedLabel(title: "Stop & Close Out", systemImage: "stop.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .padding(.horizontal, 16)
                                    .background(Color.red.opacity(0.85))
                                    .foregroundColor(.white).cornerRadius(14).font(.headline)
                            }

                            HStack(spacing: 12) {
                                StatMini(title: "Hours", value: String(format: "%.1f", s.hoursPlayed))
                                StatMini(title: "Start Pts", value: "\(s.startingTierPoints)")
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                L10nText("Tier points")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                Picker("", selection: Binding(
                                    get: { store.liveSession?.effectiveTierPointsVerification ?? .unverified },
                                    set: { store.updateLiveSessionTierPointsVerification($0) }
                                )) {
                                    Text("Verified").tag(SessionTierPointsVerification.verified)
                                    Text("Unverified").tag(SessionTierPointsVerification.unverified)
                                }
                                .pickerStyle(.segmented)
                                .tint(.green)
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(16)

                            VStack(alignment: .leading, spacing: 6) {
                                L10nText("Private notes (not shared)")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                TextEditor(text: Binding(
                                    get: { store.liveSession?.privateNotes ?? "" },
                                    set: { store.updateLiveSessionNotes($0) }
                                ))
                                .frame(minHeight: 72)
                                .padding(8)
                                .background(Color(.systemGray6).opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .scrollContentBackground(.hidden)
                            }
                        }
                        .padding()
                    }
                }
            }
            .localizedNavigationTitle("Live Session")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }.foregroundColor(.green)
                }
            }
            .onReceive(ticker) { _ in elapsed = s.duration }
            .onAppear { elapsed = s.duration }
            .adaptiveSheet(isPresented: $showBuyInSheet) {
                BuyInQuickAddSheet(quickBuyIns: quickBuyIns, onAdd: { amount in
                    store.addBuyIn(amount)
                }, onAddFreePlay: {
                    showFreePlaySheet = true
                })
                .environmentObject(settingsStore)
            }
            .adaptiveSheet(isPresented: $showFreePlaySheet) {
                FreePlayQuickAddSheet(existingSessionFreePlayTotal: store.liveSession?.totalFreePlay ?? 0) { amount, playType, photoJPEG, photoContextTags, photoCustomLabels in
                    store.addFreePlay(
                        amount: amount,
                        playType: playType,
                        photoJPEG: photoJPEG,
                        photoContextTags: photoContextTags,
                        photoCustomContextLabels: photoCustomLabels
                    )
                }
                .environmentObject(settingsStore)
            }
            .adaptiveSheet(isPresented: $showUpdateStackSheet) {
                if let live = store.liveSession, !live.isSlotsSession {
                    UpdateStackSheet(
                        sessionID: live.id,
                        game: live.game,
                        casino: live.casino,
                        stackBaseline: live.totalStackBaseline,
                        currentTrackedStack: live.liveTrackedStackAmount,
                        hoursPlayed: live.hoursPlayed,
                        onUpdate: { store.updateLiveTrackedStack($0) },
                        onAddFreePlay: { showFreePlaySheet = true }
                    )
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
                    .environment(\.appLanguage, settingsStore.appLanguage)
                }
            }
            .adaptiveSheet(isPresented: $showCompSheet) {
                CompQuickAddSheet(
                    existingSessionCompTotal: store.liveSession?.totalComp ?? 0,
                    existingSessionFreePlayTotal: store.liveSession?.totalFreePlay ?? 0,
                    sessionGame: store.liveSession?.game ?? "",
                    sessionCasino: store.liveSession?.casino ?? "",
                    sessionCasinoLatitude: store.liveSession?.casinoLatitude,
                    sessionCasinoLongitude: store.liveSession?.casinoLongitude
                ) { kind, amount, details, foodKind, otherDesc, photoJPEG, asFreePlay in
                    store.addComp(
                        amount: amount,
                        kind: kind,
                        details: details,
                        foodBeverageKind: foodKind,
                        foodBeverageOtherDescription: otherDesc,
                        photoJPEG: photoJPEG,
                        recordAsFreePlay: asFreePlay
                    )
                }
                .environmentObject(settingsStore)
                .environmentObject(subscriptionStore)
                .environmentObject(authStore)
            }
            .adaptiveSheet(isPresented: $showCloseout) {
                CloseoutView()
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(rewardWalletStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
            }
            .adaptiveSheet(isPresented: $showStrategyOdds) {
                StrategyOddsSheet(gameName: s.game)
                    .environmentObject(settingsStore)
            }
            .halfScreenSheet(isPresented: $showPrivateNotes) {
                PrivateNotesSheet(
                    notes: Binding(
                        get: { store.liveSession?.privateNotes ?? "" },
                        set: { store.updateLiveSessionNotes($0) }
                    ),
                    onDismiss: { showPrivateNotes = false }
                )
                .environmentObject(settingsStore)
            }
            #if os(iOS)
            .sheet(item: $liveSessionShareRef) { ref in
                PostCloseoutShareFlowView(sessionId: ref.id)
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
            }
            .adaptiveSheet(isPresented: $showSessionPhotos) {
                SessionPhotosSheet(sessionID: s.id)
                    .environmentObject(store)
                    .environmentObject(settingsStore)
            }
            #endif
            .onChange(of: store.liveSession) { newVal in if newVal == nil { dismiss() } }
            .alert("Missing Information", isPresented: $showMissingInfoAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please complete the following before closing out: \(missingInfoFields.joined(separator: ", ")). You can add buy-ins here, but game and location must be set when you check in.")
            }
        }
    }
}

/// Sheet for editing private session notes (local only, not shared).
struct PrivateNotesSheet: View {
    @Binding var notes: String
    let onDismiss: () -> Void
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    L10nText("Private notes (stored locally only, not shared)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(.systemGray6).opacity(0.25))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .scrollContentBackground(.hidden)
                    Spacer(minLength: 0)
                }
                .padding()
            }
            .localizedNavigationTitle("Private Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
            }
        }
    }
}
