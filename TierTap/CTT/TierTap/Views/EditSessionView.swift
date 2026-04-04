import SwiftUI
import UIKit

/// Edit an existing session from history. Updates via SessionStore.updateSession.
struct EditSessionView: View {
    let session: Session
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss

    @State private var selectedGame: String = ""
    @State private var casino: String = ""
    @State private var date: Date = Date()
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var totalBuyIn: String = ""
    @State private var cashOut: String = ""
    @State private var startingTier: String = ""
    @State private var endingTier: String = ""
    @State private var tierPointsVerification: SessionTierPointsVerification = .unverified
    @State private var avgBetActual: String = ""
    @State private var avgBetRated: String = ""
    @State private var privateNotes: String = ""

    // Casino game type metadata
    @State private var gameCategory: SessionGameCategory = .table
    @State private var pokerGameKind: SessionPokerGameKind = .cash
    @State private var pokerAllowsRebuy: Bool = false
    @State private var pokerAllowsAddOn: Bool = false
    @State private var pokerHasFreeOut: Bool = false
    @State private var pokerVariant: String = "No Limit Texas Hold’em"
    @State private var pokerSmallBlindText: String = ""
    @State private var pokerBigBlindText: String = ""
    @State private var pokerAnteText: String = ""
    @State private var pokerLevelMinutesText: String = ""
    @State private var pokerStartingStackText: String = ""
    @State private var slotNotes: String = ""
    @State private var showGamePicker = false

    /// Working copy of comps; new entries use the same storage as live sessions (`CompPhotoStorage` by event id).
    @State private var compEvents: [CompEvent] = []
    @State private var showCompSheet = false
    @State private var compToEdit: CompEvent?

    private static let quickCompAmounts: [Int] = [
        5, 10, 25, 50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 25_000, 100_000
    ]

    private var compTotal: Int { compEvents.reduce(0) { $0 + $1.amount } }
    private var compDollarsCreditsTotal: Int {
        compEvents.filter { $0.kind == .dollarsCredits }.reduce(0) { $0 + $1.amount }
    }

    // Session photo attachment
    @State private var sessionPhoto: UIImage?
    @State private var chipPhotoFilename: String?
    @State private var sessionPhotoSource: SessionPhotoSource?

    private enum SessionPhotoSource: Identifiable {
        case camera
        case photoLibrary

        var id: Int { hashValue }
    }

    var isValid: Bool {
        let hasGame: Bool = (gameCategory == .poker) ? true : !selectedGame.isEmpty
        return hasGame && !casino.isEmpty &&
        endTime > startTime &&
        Int(totalBuyIn) != nil && Int(cashOut) != nil &&
        Int(startingTier) != nil && Int(endingTier) != nil
        // Avg bet fields are optional when editing history; don't require them for save.
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            LocalizedLabel(title: "Casino Game", systemImage: "suit.club.fill")
                                .font(.headline).foregroundColor(.white)

                            GameCategoryWheelPicker(selection: $gameCategory, heading: "Game Type")
                                .environmentObject(settingsStore)

                            if gameCategory == .table || gameCategory == .slots {
                                GamePickerSelectorRow(
                                    title: selectedGame.isEmpty ? "Select game..." : selectedGame,
                                    isPlaceholder: selectedGame.isEmpty
                                ) { showGamePicker = true }
                                    .environmentObject(settingsStore)
                                if gameCategory == .slots {
                                    SlotSessionNotesOnlySection(slotNotes: $slotNotes)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        GameTypePill(title: "Cash", isSelected: pokerGameKind == .cash) {
                                            pokerGameKind = .cash
                                        }
                                        GameTypePill(title: "Tournament", isSelected: pokerGameKind == .tournament) {
                                            pokerGameKind = .tournament
                                        }
                                    }

                                    if pokerGameKind == .tournament {
                                        HStack(spacing: 8) {
                                            OptionChip(title: "Re-buy", isOn: pokerAllowsRebuy) {
                                                pokerAllowsRebuy.toggle()
                                            }
                                            OptionChip(title: "Add-On", isOn: pokerAllowsAddOn) {
                                                pokerAllowsAddOn.toggle()
                                            }
                                            OptionChip(title: "Free-Out", isOn: pokerHasFreeOut) {
                                                pokerHasFreeOut.toggle()
                                            }
                                        }
                                    }

                                    Picker("Poker Type", selection: $pokerVariant) {
                                        L10nText("No Limit Texas Hold’em").tag("No Limit Texas Hold’em")
                                        L10nText("Pot Limit Omaha").tag("Pot Limit Omaha")
                                        L10nText("Pot Limit Omaha Hi-Lo").tag("Pot Limit Omaha Hi-Lo")
                                        L10nText("Fixed Limit Hold’em").tag("Fixed Limit Hold’em")
                                        L10nText("Spread Limit Hold’em").tag("Spread Limit Hold’em")
                                        L10nText("Short Deck Hold’em (6+)").tag("Short Deck Hold’em (6+)")
                                        L10nText("Omaha Hi").tag("Omaha Hi")
                                        L10nText("Omaha Hi-Lo").tag("Omaha Hi-Lo")
                                        L10nText("5 Card Omaha").tag("5 Card Omaha")
                                        L10nText("5 Card Omaha Hi-Lo").tag("5 Card Omaha Hi-Lo")
                                        L10nText("7 Card Stud").tag("7 Card Stud")
                                        L10nText("7 Card Stud Hi-Lo").tag("7 Card Stud Hi-Lo")
                                        L10nText("Razz").tag("Razz")
                                        L10nText("5 Card Draw").tag("5 Card Draw")
                                        L10nText("2-7 Triple Draw").tag("2-7 Triple Draw")
                                        L10nText("2-7 Single Draw").tag("2-7 Single Draw")
                                        L10nText("Chinese Poker").tag("Chinese Poker")
                                        L10nText("Open Face Chinese").tag("Open Face Chinese")
                                        L10nText("Mixed Game (H.O.R.S.E.)").tag("Mixed Game (H.O.R.S.E.)")
                                        L10nText("Mixed Game (8-Game)").tag("Mixed Game (8-Game)")
                                        L10nText("Other Poker").tag("Other Poker")
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.white)

                                    VStack(alignment: .leading, spacing: 6) {
                                        L10nText("Blinds & Structure")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)

                                        HStack(spacing: 8) {
                                            TextField("SB", text: $pokerSmallBlindText)
                                                .textFieldStyle(DarkTextFieldStyle())
                                                .keyboardType(.numberPad)
                                            TextField("BB", text: $pokerBigBlindText)
                                                .textFieldStyle(DarkTextFieldStyle())
                                                .keyboardType(.numberPad)
                                            TextField("Ante", text: $pokerAnteText)
                                                .textFieldStyle(DarkTextFieldStyle())
                                                .keyboardType(.numberPad)
                                        }

                                        if pokerGameKind == .tournament {
                                            HStack(spacing: 8) {
                                                TextField("Level mins", text: $pokerLevelMinutesText)
                                                    .textFieldStyle(DarkTextFieldStyle())
                                                    .keyboardType(.numberPad)
                                                TextField("Starting stack", text: $pokerStartingStackText)
                                                    .textFieldStyle(DarkTextFieldStyle())
                                                    .keyboardType(.numberPad)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        VStack(alignment: .leading, spacing: 12) {
                            L10nText("Casino").font(.subheadline.bold()).foregroundColor(.white)
                            TextField("Casino name", text: $casino).textFieldStyle(DarkTextFieldStyle())
                            DatePicker("Date", selection: $date, displayedComponents: .date).colorScheme(.dark)
                            HStack(spacing: 12) {
                                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute).labelsHidden().colorScheme(.dark)
                                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute).labelsHidden().colorScheme(.dark)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        VStack(spacing: 12) {
                            InputRow(label: "Total Buy-In (\(settingsStore.currencySymbol))", placeholder: "Total bought in", value: $totalBuyIn)
                            InputRow(label: "Cash Out (\(settingsStore.currencySymbol))", placeholder: "Amount cashed out", value: $cashOut)
                            InputRow(label: "Starting Tier Points", placeholder: "At session start", value: $startingTier)
                            InputRow(label: "Ending Tier Points", placeholder: "At session end", value: $endingTier)
                            VStack(alignment: .leading, spacing: 6) {
                                L10nText("Tier points")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                Picker("", selection: $tierPointsVerification) {
                                    Text("Verified").tag(SessionTierPointsVerification.verified)
                                    Text("Unverified").tag(SessionTierPointsVerification.unverified)
                                }
                                .pickerStyle(.segmented)
                            }
                            InputRow(label: "Avg Bet Actual (\(settingsStore.currencySymbol))", placeholder: "Actual avg bet", value: $avgBetActual)
                            InputRow(label: "Avg Bet Rated (\(settingsStore.currencySymbol))", placeholder: "Rated avg bet", value: $avgBetRated)
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                L10nText("Comps").font(.headline).foregroundColor(.white)
                                Spacer()
                                Text("Total: \(settingsStore.currencySymbol)\(compTotal)")
                                    .font(.title3.bold()).foregroundColor(.white)
                            }
                            if compEvents.isEmpty {
                                L10nText("No comps logged yet.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            } else {
                                L10nText("Tap a row to edit, or use the menu to delete.")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                ForEach(compEvents) { ev in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Button {
                                            compToEdit = ev
                                        } label: {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Image(systemName: ev.kind.symbolName)
                                                    .foregroundColor(.green).font(.caption)
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
                                                Spacer(minLength: 4)
                                                Text(ev.timestamp, style: .time)
                                                    .font(.caption).foregroundColor(.gray)
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundColor(.gray.opacity(0.8))
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        Menu {
                                            Button("Edit") { compToEdit = ev }
                                            Button("Delete", role: .destructive) { removeComp(ev) }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .font(.title3)
                                                .foregroundColor(.white.opacity(0.75))
                                                .frame(width: 36, height: 36)
                                        }
                                    }
                                }
                            }
                            Button {
                                showCompSheet = true
                            } label: {
                                LocalizedLabel(title: "Add Comp", systemImage: "gift.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.green)
                                    .cornerRadius(14)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        VStack(alignment: .leading, spacing: 12) {
                            LocalizedLabel(title: "Session Photos", systemImage: "photo.on.rectangle.angled")
                                .font(.headline)
                                .foregroundColor(.white)

                            VStack(alignment: .leading, spacing: 6) {
                                L10nText("Session")
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
                                            L10nText("Add a photo from this session")
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
                                        LocalizedLabel(title: "Camera", systemImage: "camera")
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
                                        LocalizedLabel(title: "Photo Library", systemImage: "photo")
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
                                            chipPhotoFilename = nil
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                                .padding(8)
                                        }
                                    }
                                }
                            }

                            if compEvents.contains(where: { compHasReceiptPhoto($0.id) }) {
                                VStack(alignment: .leading, spacing: 10) {
                                    L10nText("Comp receipts")
                                        .font(.caption.bold())
                                        .foregroundColor(.gray)
                                    ForEach(compEvents.filter { compHasReceiptPhoto($0.id) }) { ev in
                                        HStack(alignment: .center, spacing: 10) {
                                            CompEventPhotoThumbnail(compEventID: ev.id, side: 52)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(ev.kind.title) · \(settingsStore.currencySymbol)\(ev.amount)")
                                                    .font(.subheadline)
                                                    .foregroundColor(.white)
                                                Text(ev.timestamp, style: .time)
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        VStack(alignment: .leading, spacing: 6) {
                            L10nText("Private notes (not shared)")
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
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        Button { save() } label: {
                            L10nText("Save Changes")
                                .frame(maxWidth: .infinity).padding()
                                .background(isValid ? Color.green : Color.gray)
                                .foregroundColor(isValid ? .black : .white)
                                .cornerRadius(14).font(.headline)
                        }
                        .disabled(!isValid)
                    }
                    .padding()
                }
            }
            .localizedNavigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.green)
                }
            }
            .onAppear { prefill() }
            .onChange(of: gameCategory) { newCat in
                if newCat != .slots {
                    slotNotes = ""
                }
            }
            .adaptiveSheet(isPresented: $showCompSheet) {
                CompQuickAddSheet(
                    existingSessionCompTotal: compTotal,
                    existingDollarsCreditsCompTotal: compDollarsCreditsTotal,
                    quickAmounts: Self.quickCompAmounts,
                    sessionGame: selectedGame,
                    sessionCasino: casino,
                    sessionCasinoLatitude: session.casinoLatitude,
                    sessionCasinoLongitude: session.casinoLongitude
                ) { kind, amount, details, foodKind, otherDesc, photoJPEG in
                    appendComp(
                        kind: kind,
                        amount: amount,
                        details: details,
                        foodBeverageKind: foodKind,
                        foodBeverageOtherDescription: otherDesc,
                        photoJPEG: photoJPEG
                    )
                }
                .environmentObject(settingsStore)
                .environmentObject(subscriptionStore)
                .environmentObject(authStore)
            }
            .adaptiveSheet(item: $compToEdit) { ev in
                EditCompEventSheet(original: ev) { updated in
                    if let i = compEvents.firstIndex(where: { $0.id == updated.id }) {
                        compEvents[i] = updated
                    }
                }
                .environmentObject(settingsStore)
            }
            .adaptiveSheet(isPresented: $showGamePicker) {
                GamePickerView(selectedGame: $selectedGame, mode: gameCategory == .slots ? .slots : .table)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
                    .gamePickerSheetPresentation()
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
        }
    }

    private func prefill() {
        selectedGame = session.game
        casino = session.casino
        date = session.startTime
        startTime = session.startTime
        endTime = session.endTime ?? session.startTime.addingTimeInterval(3600)
        totalBuyIn = "\(session.totalBuyIn)"
        cashOut = session.cashOut.map { "\($0)" } ?? ""
        startingTier = "\(session.startingTierPoints)"
        endingTier = session.endingTierPoints.map { "\($0)" } ?? ""
        tierPointsVerification = session.effectiveTierPointsVerification
        avgBetActual = session.avgBetActual.map { "\($0)" } ?? ""
        avgBetRated = session.avgBetRated.map { "\($0)" } ?? ""
        privateNotes = session.privateNotes ?? ""

        gameCategory = session.gameCategory ?? .table
        pokerGameKind = session.pokerGameKind ?? .cash
        pokerAllowsRebuy = session.pokerAllowsRebuy ?? false
        pokerAllowsAddOn = session.pokerAllowsAddOn ?? false
        pokerHasFreeOut = session.pokerHasFreeOut ?? false
        pokerVariant = session.pokerVariant ?? pokerVariant
        pokerSmallBlindText = session.pokerSmallBlind.map { "\($0)" } ?? ""
        pokerBigBlindText = session.pokerBigBlind.map { "\($0)" } ?? ""
        pokerAnteText = session.pokerAnte.map { "\($0)" } ?? ""
        pokerLevelMinutesText = session.pokerLevelMinutes.map { "\($0)" } ?? ""
        pokerStartingStackText = session.pokerStartingStack.map { "\($0)" } ?? ""
        slotNotes = session.slotNotes ?? ""

        compEvents = session.compEvents

        chipPhotoFilename = session.chipEstimatorImageFilename
        if let fileName = chipPhotoFilename,
           let url = ChipEstimatorPhotoStorage.url(for: fileName),
           let uiImage = UIImage(contentsOfFile: url.path) {
            sessionPhoto = uiImage
        }
    }

    private func save() {
        // For Poker, build a descriptive game name from the selected options.
        if gameCategory == .poker {
            var parts: [String] = []
            let kindLabel = (pokerGameKind == .cash) ? "Cash" : "Tournament"
            parts.append("Poker \(kindLabel)")
            if !pokerVariant.isEmpty {
                parts.append(pokerVariant)
            }
            if pokerGameKind == .tournament {
                var opts: [String] = []
                if pokerAllowsRebuy { opts.append("Re-buy") }
                if pokerAllowsAddOn { opts.append("Add-On") }
                if pokerHasFreeOut { opts.append("Free-Out") }
                if !opts.isEmpty {
                    parts.append(opts.joined(separator: ", "))
                }
            }
            selectedGame = parts.joined(separator: " - ")
        }

        guard let bi = Int(totalBuyIn), let co = Int(cashOut),
              let st = Int(startingTier), let et = Int(endingTier) else { return }
        let cal = Calendar.current
        let dc = cal.dateComponents([.year,.month,.day], from: date)
        let sc = cal.dateComponents([.hour,.minute], from: startTime)
        let ec = cal.dateComponents([.hour,.minute], from: endTime)
        var s1 = DateComponents(); s1.year=dc.year; s1.month=dc.month; s1.day=dc.day; s1.hour=sc.hour; s1.minute=sc.minute
        var e1 = DateComponents(); e1.year=dc.year; e1.month=dc.month; e1.day=dc.day; e1.hour=ec.hour; e1.minute=ec.minute
        let start = cal.date(from: s1) ?? date
        let end = cal.date(from: e1) ?? date.addingTimeInterval(3600)
        let ev = BuyInEvent(amount: bi, timestamp: start)
        let sb: Int? = (gameCategory == .poker) ? Int(pokerSmallBlindText) : nil
        let bb: Int? = (gameCategory == .poker) ? Int(pokerBigBlindText) : nil
        let ante: Int? = (gameCategory == .poker) ? Int(pokerAnteText) : nil
        let levelMinutes: Int? = (gameCategory == .poker && pokerGameKind == .tournament) ? Int(pokerLevelMinutesText) : nil
        let startingStack: Int? = (gameCategory == .poker && pokerGameKind == .tournament) ? Int(pokerStartingStackText) : nil
        let slotMeta = Session.persistedSlotMetadata(
            gameCategory: gameCategory,
            format: nil,
            formatOther: "",
            feature: nil,
            featureOther: "",
            notes: slotNotes
        )
        var updated = Session(
            id: session.id,
            game: selectedGame,
            casino: casino,
            casinoLatitude: session.casinoLatitude,
            casinoLongitude: session.casinoLongitude,
            startTime: start,
            endTime: end,
            startingTierPoints: st,
            endingTierPoints: et,
            buyInEvents: [ev],
            compEvents: compEvents,
            cashOut: co,
            avgBetActual: Int(avgBetActual),
            avgBetRated: Int(avgBetRated),
            isLive: false,
            status: session.status,
            sessionMood: session.sessionMood,
            privateNotes: privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes,
            rewardsProgramName: session.rewardsProgramName,
            tierPointsVerification: tierPointsVerification,
            chipEstimatorImageFilename: chipPhotoFilename,
            gameCategory: gameCategory,
            pokerGameKind: gameCategory == .poker ? pokerGameKind : nil,
            pokerAllowsRebuy: (gameCategory == .poker && pokerGameKind == .tournament) ? pokerAllowsRebuy : nil,
            pokerAllowsAddOn: (gameCategory == .poker && pokerGameKind == .tournament) ? pokerAllowsAddOn : nil,
            pokerHasFreeOut: (gameCategory == .poker && pokerGameKind == .tournament) ? pokerHasFreeOut : nil,
            pokerVariant: gameCategory == .poker ? pokerVariant : nil,
            pokerSmallBlind: sb,
            pokerBigBlind: bb,
            pokerAnte: ante,
            pokerLevelMinutes: levelMinutes,
            pokerStartingStack: startingStack,
            slotFormat: slotMeta.format,
            slotFormatOther: slotMeta.formatOther,
            slotFeature: slotMeta.feature,
            slotFeatureOther: slotMeta.featureOther,
            slotNotes: slotMeta.notes
        )
        store.updateSession(updated)
        dismiss()
    }

    private struct GameTypePill: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.green : Color(.systemGray6).opacity(0.25))
                    .foregroundColor(isSelected ? .black : .white)
                    .clipShape(Capsule())
            }
        }
    }

    private struct OptionChip: View {
        let title: String
        let isOn: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isOn ? Color.green.opacity(0.2) : Color(.systemGray6).opacity(0.25))
                    .foregroundColor(isOn ? .green : .white)
                    .cornerRadius(8)
            }
        }
    }

    private func handlePickedSessionPhoto(_ image: UIImage) {
        sessionPhoto = image
        if let fileName = ChipEstimatorPhotoStorage.saveImage(image, for: session.id) {
            chipPhotoFilename = fileName
        }
    }

    private func compHasReceiptPhoto(_ id: UUID) -> Bool {
        guard let url = CompPhotoStorage.url(for: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func removeComp(_ ev: CompEvent) {
        if compToEdit?.id == ev.id {
            compToEdit = nil
        }
        #if os(iOS)
        CompPhotoStorage.deleteImage(compEventID: ev.id)
        #endif
        compEvents.removeAll { $0.id == ev.id }
    }

    /// Mirrors `SessionStore.addComp` for the edited session’s working `compEvents` list.
    private func appendComp(
        kind: CompKind,
        amount: Int,
        details: String?,
        foodBeverageKind: FoodBeverageKind?,
        foodBeverageOtherDescription: String?,
        photoJPEG: Data?
    ) {
        let trimmed = details?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedDetails = (trimmed?.isEmpty == false) ? trimmed : nil
        let storedFB: FoodBeverageKind? = (kind == .foodBeverage) ? foodBeverageKind : nil
        let trimmedOther = foodBeverageOtherDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedOther: String? = (kind == .foodBeverage && storedFB == .other && trimmedOther?.isEmpty == false) ? trimmedOther : nil
        let eventId = UUID()
        let ev = CompEvent(
            id: eventId,
            amount: amount,
            timestamp: Date(),
            kind: kind,
            details: storedDetails,
            foodBeverageKind: storedFB,
            foodBeverageOtherDescription: storedOther
        )
        compEvents.append(ev)
        #if os(iOS)
        if let jpeg = photoJPEG {
            CompPhotoStorage.saveJPEGData(jpeg, compEventID: eventId)
        }
        #endif
    }
}

/// Edit an existing comp while preserving `CompEvent.id` so receipt photos stay linked on disk.
private struct EditCompEventSheet: View {
    let original: CompEvent
    let onSave: (CompEvent) -> Void

    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var selectedKind: CompKind
    @State private var detailsText: String
    @State private var foodBeverageKind: FoodBeverageKind
    @State private var foodBeverageOtherText: String
    @State private var timestamp: Date
    @State private var compPhoto: UIImage?
    @State private var photoExplicitlyRemoved = false
    @State private var compPhotoSource: CompPhotoSource?

    private enum CompPhotoSource: Identifiable {
        case camera
        case photoLibrary

        var id: Int { hashValue }
    }

    init(original: CompEvent, onSave: @escaping (CompEvent) -> Void) {
        self.original = original
        self.onSave = onSave
        _amountText = State(initialValue: "\(original.amount)")
        _selectedKind = State(initialValue: original.kind)
        _detailsText = State(initialValue: original.details ?? "")
        _foodBeverageKind = State(initialValue: original.foodBeverageKind ?? .meal)
        _foodBeverageOtherText = State(initialValue: original.foodBeverageOtherDescription ?? "")
        _timestamp = State(initialValue: original.timestamp)
    }

    private var parsedAmount: Int? {
        Int(amountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSave: Bool {
        guard let a = parsedAmount, a > 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Amount (\(settingsStore.currencySymbol))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gray)
                            TextField("0", text: $amountText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(DarkTextFieldStyle())
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            L10nText("Comp type")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gray)
                            HStack(spacing: 8) {
                                compKindPill(.dollarsCredits)
                                compKindPill(.foodBeverage)
                            }
                        }

                        if selectedKind == .foodBeverage {
                            Picker("Food & beverage", selection: $foodBeverageKind) {
                                ForEach(FoodBeverageKind.allCases, id: \.self) { k in
                                    Text(k.label).tag(k)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)

                            if foodBeverageKind == .other {
                                TextField("Describe (e.g. buffet)", text: $foodBeverageOtherText)
                                    .textFieldStyle(DarkTextFieldStyle())
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            L10nText("Details (optional)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gray)
                            TextField("Host name, promo…", text: $detailsText, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(DarkTextFieldStyle())
                        }

                        DatePicker("Date & time", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                            .colorScheme(.dark)

                        VStack(alignment: .leading, spacing: 8) {
                            L10nText("Receipt photo")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gray)
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6]))
                                    .background(Color(.systemGray6).opacity(0.2))
                                    .cornerRadius(12)

                                if let img = compPhoto {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(10)
                                        .padding(4)
                                } else {
                                    Text(photoExplicitlyRemoved ? "Photo removed" : "No photo")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(16)
                                }
                            }
                            .frame(maxHeight: 180)

                            HStack(spacing: 12) {
                                Button {
                                    compPhotoSource = .camera
                                } label: {
                                    LocalizedLabel(title: "Camera", systemImage: "camera")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.9))
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                }
                                Button {
                                    compPhotoSource = .photoLibrary
                                } label: {
                                    LocalizedLabel(title: "Library", systemImage: "photo")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6).opacity(0.35))
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                }
                                if compPhoto != nil {
                                    Button(role: .destructive) {
                                        compPhoto = nil
                                        photoExplicitlyRemoved = true
                                    } label: {
                                        LocalizedLabel(title: "Remove", systemImage: "trash")
                                            .font(.caption.bold())
                                    }
                                }
                            }
                        }

                        Button {
                            save()
                        } label: {
                            L10nText("Save comp")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(canSave ? Color.green : Color.gray)
                                .foregroundColor(canSave ? .black : .white)
                                .cornerRadius(14)
                        }
                        .disabled(!canSave)
                    }
                    .padding()
                }
            }
            .localizedNavigationTitle("Edit comp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.green)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            if let url = CompPhotoStorage.url(for: original.id),
               let img = UIImage(contentsOfFile: url.path) {
                compPhoto = img
            }
        }
        .adaptiveSheet(item: $compPhotoSource) { source in
            switch source {
            case .camera:
                CameraPicker(selectedImage: .constant(nil)) { image in
                    compPhoto = image
                    photoExplicitlyRemoved = false
                }
            case .photoLibrary:
                ImagePicker(selectedImage: .constant(nil)) { image in
                    compPhoto = image
                    photoExplicitlyRemoved = false
                }
            }
        }
    }

    private func compKindPill(_ kind: CompKind) -> some View {
        Button {
            selectedKind = kind
        } label: {
            Text(kind.title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedKind == kind ? Color.green : Color(.systemGray6).opacity(0.25))
                .foregroundColor(selectedKind == kind ? .black : .white)
                .clipShape(Capsule())
        }
    }

    private func save() {
        guard let amt = parsedAmount, amt > 0 else { return }
        let trimmedDetails = detailsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let details: String? = trimmedDetails.isEmpty ? nil : trimmedDetails
        let fb: FoodBeverageKind? = (selectedKind == .foodBeverage) ? foodBeverageKind : nil
        let otherTrim = foodBeverageOtherText.trimmingCharacters(in: .whitespacesAndNewlines)
        let other: String? = (selectedKind == .foodBeverage && fb == .other && !otherTrim.isEmpty) ? otherTrim : nil

        let updated = CompEvent(
            id: original.id,
            amount: amt,
            timestamp: timestamp,
            kind: selectedKind,
            details: details,
            foodBeverageKind: fb,
            foodBeverageOtherDescription: other
        )
        if photoExplicitlyRemoved {
            CompPhotoStorage.deleteImage(compEventID: original.id)
        } else if let img = compPhoto, let jpeg = img.jpegData(compressionQuality: 0.9) {
            CompPhotoStorage.saveJPEGData(jpeg, compEventID: original.id)
        }
        onSave(updated)
        dismiss()
    }
}
