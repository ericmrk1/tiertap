import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @State private var bankrollText: String = ""
    @State private var unitSizeText: String = ""
    @State private var targetAverageText: String = ""
    @State private var denominationsText: String = ""
    @State private var primaryColorSelection: Color = .green
    @State private var secondaryColorSelection: Color = .blue
    @State private var isBankrollExpanded: Bool = false
    @State private var isRiskOfRuinExpanded: Bool = false
    @State private var isSessionsExpanded: Bool = false
    @State private var isQuickButtonsExpanded: Bool = false
    @State private var isFavoritesExpanded: Bool = false
    @State private var isThemeExpanded: Bool = false
    @State private var isSocialLoginsExpanded: Bool = false
    @State private var isDataExportExpanded: Bool = false
    @State private var isAboutExpanded: Bool = false
    @State private var isPresentingShareSheet: Bool = false
    @State private var isShowingGamePicker: Bool = false
    @State private var isShowingCasinoPicker: Bool = false
    @State private var exportFileURL: URL?
    @State private var isExporting: Bool = false
    @State private var exportErrorMessage: String?
    @State private var isShowingExportError: Bool = false
    @State private var gamePickerSelection: String = ""
    @State private var casinoPickerSelection: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        bankrollSection
                        riskOfRuinSection
                        sessionsSection
                        quickButtonsSection
                        favoritesSection
                        themeSection
                        socialLoginsSection
                        dataExportSection
                        aboutSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                bankrollText = settingsStore.bankroll > 0 ? "\(settingsStore.bankroll)" : ""
                unitSizeText = settingsStore.unitSize > 0 ? "\(settingsStore.unitSize)" : ""
                if let t = settingsStore.targetAveragePerSession {
                    targetAverageText = String(format: "%.0f", t)
                } else {
                    targetAverageText = ""
                }
                denominationsText = settingsStore.commonDenominations.map { "\($0)" }.joined(separator: ", ")
                primaryColorSelection = settingsStore.primaryColor
                secondaryColorSelection = settingsStore.secondaryColor
            }
            .onChange(of: gamePickerSelection) { new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if !settingsStore.favoriteGames.contains(trimmed) {
                    settingsStore.favoriteGames.append(trimmed)
                }
            }
            .onChange(of: casinoPickerSelection) { new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if !settingsStore.favoriteCasinos.contains(trimmed) {
                    settingsStore.favoriteCasinos.append(trimmed)
                }
            }
            .sheet(isPresented: $isPresentingShareSheet, onDismiss: {
                exportFileURL = nil
            }) {
                if let url = exportFileURL {
                    ShareSheet(items: [url])
                } else {
                    Text("Nothing to share.")
                        .padding()
                }
            }
            .alert("Export Failed", isPresented: $isShowingExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportErrorMessage ?? "An unknown error occurred while exporting your data.")
            }
            .sheet(isPresented: $isShowingGamePicker) {
                GamePickerView(selectedGame: $gamePickerSelection)
            }
            .sheet(isPresented: $isShowingCasinoPicker) {
                CasinoLocationPickerView(selectedCasino: $casinoPickerSelection)
            }
        }
    }

    private var bankrollSection: some View {
        SettingsSection(
            title: "Bankroll & Units",
            systemImage: "dollarsign.circle.fill",
            isExpanded: $isBankrollExpanded
        ) {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Currency")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Picker("", selection: $settingsStore.currencyCode) {
                        ForEach(Currency.all) { currency in
                            let countryPart = currency.country ?? currency.name
                            Text("\(currency.code) \(currency.symbol) — \(countryPart)")
                                .tag(currency.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .clipped()
                }
                .padding()
                .background(Color(.systemGray6).opacity(0.15))
                .cornerRadius(12)

                InputRow(label: "Bankroll (\(settingsStore.currencySymbol))", placeholder: "Total bankroll", value: $bankrollText)
                    .onChange(of: bankrollText) { new in
                        if let v = Int(new.filter { $0.isNumber }) { settingsStore.bankroll = v }
                    }
                InputRow(label: "Unit size (\(settingsStore.currencySymbol))", placeholder: "Max bet per unit (recommended 1–2% of bankroll)", value: $unitSizeText)
                    .onChange(of: unitSizeText) { new in
                        if let v = Int(new.filter { $0.isNumber }) { settingsStore.unitSize = v }
                    }
            }
            Text("Risk of Ruin uses bankroll and unit size. Keep bets at or below unit size to stay within target risk.")
                .font(.caption).foregroundColor(.gray)
        }
    }

    private var riskOfRuinSection: some View {
        SettingsSection(
            title: "Target average",
            systemImage: "target",
            isExpanded: $isRiskOfRuinExpanded
        ) {
            InputRow(label: "Target win per session (\(settingsStore.currencySymbol))", placeholder: "Optional — e.g. 100", value: $targetAverageText)
                .onChange(of: targetAverageText) { new in
                    let n = new.replacingOccurrences(of: ",", with: ".")
                    if n.isEmpty {
                        settingsStore.targetAveragePerSession = nil
                    } else if let v = Double(n.filter { $0.isNumber || $0 == "." }) {
                        settingsStore.targetAveragePerSession = v
                    }
                }
            Text("Compare your actual average win/loss per session to this target in the Risk of Ruin screen.")
                .font(.caption).foregroundColor(.gray)
        }
    }

    private var sessionsSection: some View {
        SettingsSection(
            title: "Sessions",
            systemImage: "calendar.badge.clock",
            isExpanded: $isSessionsExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Prompt for session mood after ending", isOn: $settingsStore.promptSessionMood)
                    .tint(.green)
                Text("When on, after saving a session you’ll see a grid to pick how the session felt (e.g. Great, Tilt). When off, the mood step is skipped.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private var quickButtonsSection: some View {
        SettingsSection(
            title: "Quick amounts",
            systemImage: "square.grid.2x2",
            isExpanded: $isQuickButtonsExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Common denominations")
                    .font(.subheadline.bold()).foregroundColor(.white)
                TextField("e.g. 20, 100, 500, 1000, 10000", text: $denominationsText)
                    .textFieldStyle(DarkTextFieldStyle())
                    .keyboardType(.numbersAndPunctuation)
                    .onChange(of: denominationsText) { new in
                        let parts = new.split(separator: ",")
                        let nums = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                        if !nums.isEmpty {
                            settingsStore.commonDenominations = nums
                        }
                    }
                Toggle("Use \(settingsStore.currencySymbol)18 increment mode", isOn: $settingsStore.useEighteenXMultipliers)
                    .tint(.green)
                Text("When enabled, quick buttons use each denomination ×18 (e.g. 20 → 360) for \(settingsStore.currencySymbol)18-style bets.")
                    .font(.caption).foregroundColor(.gray)
            }
        }
    }

    private var favoritesSection: some View {
        SettingsSection(
            title: "Favorites",
            systemImage: "star.fill",
            isExpanded: $isFavoritesExpanded
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Favorite casino games")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    
                    if settingsStore.favoriteGames.isEmpty {
                        Text("No favorite games yet. Tap **Add game from picker** to select from the game list.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(settingsStore.favoriteGames, id: \.self) { game in
                                    HStack(spacing: 6) {
                                        Text(game)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Button {
                                            settingsStore.favoriteGames.removeAll { $0 == game }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.white.opacity(0.9))
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6).opacity(0.3))
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                    
                    Button {
                        gamePickerSelection = ""
                        isShowingGamePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add game from picker")
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6).opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Common casino locations")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    
                    if settingsStore.favoriteCasinos.isEmpty {
                        Text("No favorite locations yet. Tap **Add casino from picker** to select from the casino map/search.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(settingsStore.favoriteCasinos, id: \.self) { casino in
                                    HStack(spacing: 6) {
                                        Text(casino)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Button {
                                            settingsStore.favoriteCasinos.removeAll { $0 == casino }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.white.opacity(0.9))
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6).opacity(0.3))
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                    
                    Button {
                        casinoPickerSelection = ""
                        isShowingCasinoPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add casino from picker")
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6).opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    private var themeSection: some View {
        SettingsSection(
            title: "Theme & colors",
            systemImage: "paintbrush.fill",
            isExpanded: $isThemeExpanded
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Preset buttons
                VStack(alignment: .leading, spacing: 8) {
                    Text("Presets")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(settingsStore.themePresets) { preset in
                                let isSelected = preset.primaryHex == settingsStore.effectivePrimaryHex &&
                                                 preset.secondaryHex == settingsStore.effectiveSecondaryHex

                                Button {
                                    applyThemePreset(preset)
                                } label: {
                                    HStack(spacing: 6) {
                                        let colors = settingsStore.colors(for: preset)
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                LinearGradient(
                                                    colors: [colors.0, colors.1],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 28, height: 16)
                                        Text(preset.name)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.white.opacity(0.9) : Color(.systemGray6).opacity(0.3))
                                    .foregroundColor(isSelected ? .black : .white)
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }

                    Button {
                        settingsStore.saveCurrentThemeAsPreset()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Save current as preset")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6).opacity(0.35))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }

                Divider().background(Color.gray.opacity(0.3))

                // Custom color pickers
                VStack(alignment: .leading, spacing: 10) {
                    Text("Custom colors")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Primary")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            ColorPicker("Primary color", selection: $primaryColorSelection, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: primaryColorSelection) { new in
                                    settingsStore.setPrimaryColor(new)
                                }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Secondary")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            ColorPicker("Secondary color", selection: $secondaryColorSelection, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: secondaryColorSelection) { new in
                                    settingsStore.setSecondaryColor(new)
                                }
                        }
                    }
                }

                RoundedRectangle(cornerRadius: 12)
                    .fill(settingsStore.primaryGradient)
                    .frame(height: 44)
                    .overlay(
                        HStack {
                            Text("Preview")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Text("Primary → Secondary")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                    )
            }
        }
    }

    // MARK: - Theme presets helpers

    private func applyThemePreset(_ preset: ThemePreset) {
        settingsStore.applyThemePreset(preset)
        primaryColorSelection = settingsStore.primaryColor
        secondaryColorSelection = settingsStore.secondaryColor
    }

    private var socialLoginsSection: some View {
        SettingsSection(
            title: "Account",
            systemImage: "person.crop.circle.fill",
            isExpanded: $isSocialLoginsExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !SupabaseConfig.isConfigured {
                    Text("Add Supabase keys to enable sign-in and sync.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else if authStore.isSignedIn {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(settingsStore.primaryGradient)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                            if let name = authStore.userFullName, !name.isEmpty {
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.95))
                            }
                            if let email = authStore.userEmail {
                                Text(email)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        Spacer()
                        Button("Sign out", role: .destructive) {
                            authStore.signOut()
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("You're not signed in. Open the **Community** tab to sign in with Apple, Google, or a magic link email.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var dataExportSection: some View {
        SettingsSection(
            title: "Data & Export",
            systemImage: "square.and.arrow.up.on.square",
            isExpanded: $isDataExportExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    exportSessionsAsCSV()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export sessions as CSV")
                            .font(.subheadline.bold())
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6).opacity(0.25))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(sessionStore.sessions.isEmpty || isExporting)

                Text("Exports your recorded sessions to a .csv file so you can back up your data or analyze it elsewhere. Uses the iOS Share sheet to send to Files, email, or other apps.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(
            title: "About",
            systemImage: "info.circle.fill",
            isExpanded: $isAboutExpanded
        ) {
            VStack(spacing: 10) {
                if let gaURL = URL(string: "https://www.gamblersanonymous.org/") {
                    Link(destination: gaURL) {
                        HStack {
                            Image(systemName: "heart.circle.fill")
                            Text("If you need help — Gamblers Anonymous")
                                .font(.subheadline.bold())
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    }
                }
                Link(destination: URL(string: "https://travelzork.com/privacy-policy/")!) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                        Text("Privacy")
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                }
                Link(destination: URL(string: "https://travelzork.com/")!) {
                    HStack {
                        Image(systemName: "heart.fill")
                        Text("Sponsor")
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                }
                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                        Text("EULA")
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private func exportSessionsAsCSV() {
        guard !sessionStore.sessions.isEmpty else { return }
        isExporting = true

        let sessions = sessionStore.sessions

        DispatchQueue.global(qos: .userInitiated).async {
            let csv = buildCSV(for: sessions)

            do {
                let url = try saveCSVToTemporaryFile(csv: csv)
                DispatchQueue.main.async {
                    self.exportFileURL = url
                    self.isExporting = false
                    self.isPresentingShareSheet = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.exportErrorMessage = error.localizedDescription
                    self.isShowingExportError = true
                }
            }
        }
    }

    private func buildCSV(for sessions: [Session]) -> String {
        var lines: [String] = []

        let headers = [
            "id",
            "game",
            "casino",
            "start_time",
            "end_time",
            "duration_hours",
            "total_buy_in",
            "cash_out",
            "win_loss",
            "avg_bet_actual",
            "avg_bet_rated",
            "starting_tier_points",
            "ending_tier_points",
            "tier_points_earned",
            "tiers_per_hour",
            "tiers_per_100_rated_bet_hour",
            "status"
        ]
        lines.append(headers.joined(separator: ","))

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for s in sessions {
            let start = dateFormatter.string(from: s.startTime)
            let end = s.endTime.map { dateFormatter.string(from: $0) } ?? ""
            let durationHours = s.hoursPlayed

            let totalBuyIn = s.totalBuyIn
            let cashOut = s.cashOut.map { String($0) } ?? ""
            let winLoss = s.winLoss.map { String($0) } ?? ""

            let avgBetActual = s.avgBetActual.map { String($0) } ?? ""
            let avgBetRated = s.avgBetRated.map { String($0) } ?? ""

            let startingTier = String(s.startingTierPoints)
            let endingTier = s.endingTierPoints.map { String($0) } ?? ""
            let tierEarned = s.tierPointsEarned.map { String($0) } ?? ""

            let tiersPerHour = s.tiersPerHour.map { String(format: "%.4f", $0) } ?? ""
            let tiersPerHundred = s.tiersPerHundredRatedBetHour.map { String(format: "%.4f", $0) } ?? ""

            let fields: [String] = [
                s.id.uuidString,
                s.game,
                s.casino,
                start,
                end,
                String(format: "%.4f", durationHours),
                String(totalBuyIn),
                cashOut,
                winLoss,
                avgBetActual,
                avgBetRated,
                startingTier,
                endingTier,
                tierEarned,
                tiersPerHour,
                tiersPerHundred,
                s.status.rawValue
            ].map { escapeCSVField($0) }

            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private func saveCSVToTemporaryFile(csv: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let fileName = "TierTap\(timestamp).csv"
        let url = tempDir.appendingPathComponent(fileName)

        guard let data = csv.data(using: .utf8) else {
            throw NSError(domain: "TierTap.Settings", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode CSV data as UTF-8."])
        }

        try data.write(to: url, options: .atomic)
        return url
    }

    private func escapeCSVField(_ value: String) -> String {
        var field = value
        if field.contains("\"") {
            field = field.replacingOccurrences(of: "\"", with: "\"\"")
        }
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            field = "\"\(field)\""
        }
        return field
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

