import SwiftUI
import UIKit

/// Edit an existing session from history. Updates via SessionStore.updateSession.
struct EditSessionView: View {
    let session: Session
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
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
    @State private var showGamePicker = false

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
                            Label("Casino Game", systemImage: "suit.club.fill")
                                .font(.headline).foregroundColor(.white)

                            HStack(spacing: 8) {
                                GameTypePill(title: "Table", isSelected: gameCategory == .table) {
                                    gameCategory = .table
                                }
                                GameTypePill(title: "Poker", isSelected: gameCategory == .poker) {
                                    gameCategory = .poker
                                    if pokerVariant.isEmpty {
                                        pokerVariant = "No Limit Texas Hold’em"
                                    }
                                }
                            }

                            if gameCategory == .table {
                                Button { showGamePicker = true } label: {
                                    HStack {
                                        Text(selectedGame.isEmpty ? "Select game..." : selectedGame)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .padding(12)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(selectedGame.isEmpty ? .gray : .white)
                                    .cornerRadius(10)
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
                                        Text("No Limit Texas Hold’em").tag("No Limit Texas Hold’em")
                                        Text("Pot Limit Omaha").tag("Pot Limit Omaha")
                                        Text("Pot Limit Omaha Hi-Lo").tag("Pot Limit Omaha Hi-Lo")
                                        Text("Fixed Limit Hold’em").tag("Fixed Limit Hold’em")
                                        Text("Spread Limit Hold’em").tag("Spread Limit Hold’em")
                                        Text("Short Deck Hold’em (6+)").tag("Short Deck Hold’em (6+)")
                                        Text("Omaha Hi").tag("Omaha Hi")
                                        Text("Omaha Hi-Lo").tag("Omaha Hi-Lo")
                                        Text("5 Card Omaha").tag("5 Card Omaha")
                                        Text("5 Card Omaha Hi-Lo").tag("5 Card Omaha Hi-Lo")
                                        Text("7 Card Stud").tag("7 Card Stud")
                                        Text("7 Card Stud Hi-Lo").tag("7 Card Stud Hi-Lo")
                                        Text("Razz").tag("Razz")
                                        Text("5 Card Draw").tag("5 Card Draw")
                                        Text("2-7 Triple Draw").tag("2-7 Triple Draw")
                                        Text("2-7 Single Draw").tag("2-7 Single Draw")
                                        Text("Chinese Poker").tag("Chinese Poker")
                                        Text("Open Face Chinese").tag("Open Face Chinese")
                                        Text("Mixed Game (H.O.R.S.E.)").tag("Mixed Game (H.O.R.S.E.)")
                                        Text("Mixed Game (8-Game)").tag("Mixed Game (8-Game)")
                                        Text("Other Poker").tag("Other Poker")
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.white)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Blinds & Structure")
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
                            Text("Casino").font(.subheadline.bold()).foregroundColor(.white)
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
                            InputRow(label: "Avg Bet Actual (\(settingsStore.currencySymbol))", placeholder: "Actual avg bet", value: $avgBetActual)
                            InputRow(label: "Avg Bet Rated (\(settingsStore.currencySymbol))", placeholder: "Rated avg bet", value: $avgBetRated)
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

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
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

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
                                        Text("Add a photo from this session")
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
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        Button { save() } label: {
                            Text("Save Changes")
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
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.green)
                }
            }
            .onAppear { prefill() }
            .adaptiveSheet(isPresented: $showGamePicker) {
                GamePickerView(selectedGame: $selectedGame).presentationDetents([.medium, .large])
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
        var updated = Session(
            id: session.id,
            game: selectedGame,
            casino: casino,
            startTime: start,
            endTime: end,
            startingTierPoints: st,
            endingTierPoints: et,
            buyInEvents: [ev],
            cashOut: co,
            avgBetActual: Int(avgBetActual),
            avgBetRated: Int(avgBetRated),
            isLive: false,
            status: session.status,
            sessionMood: session.sessionMood,
            privateNotes: privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes,
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
            pokerStartingStack: startingStack
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
}
