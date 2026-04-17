import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @State private var bankrollText: String = ""
    @State private var unitSizeText: String = ""
    @State private var targetAverageText: String = ""
    @State private var denominationsText: String = ""
    @State private var primaryColorSelection: Color = .black
    @State private var secondaryColorSelection: Color = .blue
    @State private var isBankrollExpanded: Bool = false
    @State private var isRiskOfRuinExpanded: Bool = false
    @State private var isSessionsExpanded: Bool = false
    @State private var isFavoritesExpanded: Bool = false
    @State private var isThemeExpanded: Bool = false
    @State private var isDataExportExpanded: Bool = false
    @State private var isAboutExpanded: Bool = false
    @State private var isTierTapAIExpanded: Bool = false
    @State private var isAccountExpanded: Bool = true
    @State private var isPresentingShareSheet: Bool = false
    @State private var isShowingGamePicker: Bool = false
    @State private var isShowingSlotGamePicker: Bool = false
    @State private var isShowingCasinoPicker: Bool = false
    @State private var isShowingSubscriptionPaywall: Bool = false
    @State private var exportFileURL: URL?
    @State private var isExporting: Bool = false
    @State private var exportErrorMessage: String?
    @State private var isShowingExportError: Bool = false
    @State private var gamePickerSelection: String = ""
    @State private var slotGamePickerSelection: String = ""
    @State private var casinoPickerSelection: String = ""
    @State private var subscriptionOverrideText: String = ""
    @State private var exportGameCategory: SessionGameCategory = .table
    @State private var showDenominationDialPad = false
    @State private var denominationDialPadDraft = ""

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        aboutSection
                        accountSection
                        bankrollSection
                        riskOfRuinSection
                        favoritesSection
                        sessionsSection
                        themeSection
                        tierTapAISection
                        dataExportSection
                    }
                    .padding()
                }
            }
            .localizedNavigationTitle("Settings")
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
                subscriptionOverrideText = settingsStore.subscriptionOverrideCode
                exportGameCategory = settingsStore.defaultGameCategory
            }
            .onChange(of: gamePickerSelection) { new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if !settingsStore.favoriteGames.contains(trimmed) {
                    settingsStore.favoriteGames.append(trimmed)
                }
            }
            .onChange(of: slotGamePickerSelection) { new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if !settingsStore.favoriteSlotGames.contains(trimmed) {
                    settingsStore.favoriteSlotGames.append(trimmed)
                }
            }
            .onChange(of: casinoPickerSelection) { new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if !settingsStore.favoriteCasinos.contains(trimmed) {
                    settingsStore.favoriteCasinos.append(trimmed)
                }
            }
            .adaptiveSheet(isPresented: $isPresentingShareSheet, onDismiss: {
                exportFileURL = nil
            }) {
                if let url = exportFileURL {
                    ShareSheet(items: [url])
                } else {
                    L10nText("Nothing to share.")
                        .padding()
                }
            }
            .alert("Export Failed", isPresented: $isShowingExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportErrorMessage ?? "An unknown error occurred while exporting your data.")
            }
            .adaptiveSheet(isPresented: $isShowingGamePicker) {
                GamePickerView(selectedGame: $gamePickerSelection, mode: .table)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
                    .gamePickerSheetPresentation()
            }
            .adaptiveSheet(isPresented: $isShowingSlotGamePicker) {
                GamePickerView(selectedGame: $slotGamePickerSelection, mode: .slots)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
                    .gamePickerSheetPresentation()
            }
            .adaptiveSheet(isPresented: $isShowingCasinoPicker) {
                CasinoLocationPickerView(selectedCasino: $casinoPickerSelection, selectedLatitude: .constant(nil), selectedLongitude: .constant(nil))
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
            }
            .adaptiveSheet(isPresented: $isShowingSubscriptionPaywall) {
                TierTapPaywallView()
                    .environmentObject(subscriptionStore)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
            }
        }
    }

    private var bankrollSection: some View {
        SettingsSection(
            title: "Bankroll & Localization",
            systemImage: "dollarsign.circle.fill",
            isExpanded: $isBankrollExpanded
        ) {
            VStack(spacing: 10) {
                InputRow(
                    label: "Bankroll (\(settingsStore.currencySymbol))",
                    placeholder: "Total bankroll",
                    value: $bankrollText,
                    dialPadNavigationTitle: "Bankroll"
                )
                    .onChange(of: bankrollText) { new in
                        if let v = Int(new.filter { $0.isNumber }) { settingsStore.bankroll = v }
                    }
                InputRow(
                    label: "Unit size (\(settingsStore.currencySymbol))",
                    placeholder: "Max bet per unit (recommended 1–2% of bankroll)",
                    value: $unitSizeText,
                    dialPadNavigationTitle: "Unit size"
                )
                    .onChange(of: unitSizeText) { new in
                        if let v = Int(new.filter { $0.isNumber }) { settingsStore.unitSize = v }
                    }

                VStack(alignment: .leading, spacing: 6) {
                    L10nText("Currency")
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

                VStack(alignment: .leading, spacing: 6) {
                    L10nText("App language")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Picker("App language", selection: $settingsStore.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.pickerLabel).tag(lang).foregroundColor(.secondary)
                        }
                    }
                    .pickerStyle(.menu)
                    L10nText("Controls the language for TierTap screens and for TierTap AI replies.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.top, 4)
            }
            L10nText("Risk of Ruin for table games uses bankroll and unit size. Keep table-game bets at or below unit size to stay within target risk; poker sessions are not included.")
                .font(.caption).foregroundColor(.gray)
        }
    }

    private var riskOfRuinSection: some View {
        SettingsSection(
            title: "Target average",
            systemImage: "target",
            isExpanded: $isRiskOfRuinExpanded
        ) {
            InputRow(
                label: "Target win per session (\(settingsStore.currencySymbol))",
                placeholder: "Optional — e.g. 100",
                value: $targetAverageText,
                dialPadNavigationTitle: "Target win per session"
            )
                .onChange(of: targetAverageText) { new in
                    let n = new.replacingOccurrences(of: ",", with: ".")
                    if n.isEmpty {
                        settingsStore.targetAveragePerSession = nil
                    } else if let v = Double(n.filter { $0.isNumber || $0 == "." }) {
                        settingsStore.targetAveragePerSession = v
                    }
                }
            L10nText("Compare your actual average win/loss per table-game session to this target in the Risk of Ruin screen (poker is excluded).")
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
                Toggle(isOn: $settingsStore.promptSessionMood) {
                    L10nText("Prompt for session mood after ending")
                }
                    .tint(.green)
                L10nText("When on, after saving a session you’ll see a grid to pick how the session felt (e.g. Great, Tilt). When off, the mood step is skipped.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private var tierTapAISection: some View {
        SettingsSection(
            title: "TierTap AI",
            systemImage: "wand.and.stars",
            isExpanded: $isTierTapAIExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                L10nText("Tone of voice")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Picker("Tone of voice", selection: $settingsStore.aiTone) {
                    ForEach(SettingsStore.AITone.allCases) { tone in
                        Text(L10n.tr(tone.displayName, language: settingsStore.appLanguage)).tag(tone)
                    }
                }
                .pickerStyle(.segmented)

                L10nText("Controls how the TierTap AI summarizes your sessions. Default is **Sarcastic**.")
                    .font(.caption)
                    .foregroundColor(.gray)

                L10nText("Typing speed")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        L10nText("Slow")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(L10n.tr(settingsStore.aiTypingSpeed.displayName, language: settingsStore.appLanguage))
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        Spacer()
                        L10nText("Fast")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Slider(
                        value: Binding(
                            get: { settingsStore.aiTypingSpeed.sliderIndex },
                            set: { settingsStore.aiTypingSpeed = SettingsStore.AITypingSpeed.fromSliderIndex($0) }
                        ),
                        in: 0...2,
                        step: 1
                    )
                    .tint(.green)
                }
                L10nText("How quickly AI answers appear character by character in **Ask TierTap**. Slow matches the original pace.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private var accountSection: some View {
        SettingsSection(
            title: "Account",
            systemImage: "person.crop.circle.fill",
            isExpanded: $isAccountExpanded
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    L10nText("Subscriptions")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    Button {
                        isShowingSubscriptionPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill")
                            Text(hasProAccess ? "Manage TierTap Pro" : "Upgrade to TierTap Pro")
                                .font(.subheadline.bold())
                            Spacer()
                            if hasProAccess {
                                L10nText("Active")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.15))
                                    .cornerRadius(6)
                            }
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6).opacity(0.25))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    L10nText("AI Play Analysis, Chip Estimator at close-out, and the Community feed all require an active TierTap Pro subscription and a signed-in TierTap account.")
                        .font(.caption)
                        .foregroundColor(.gray)

                    VStack(alignment: .leading, spacing: 6) {
                        L10nText("Developer subscription override")
                            .font(.caption.bold())
                            .foregroundColor(.gray)
                        NumericEntryWithDialPad(
                            placeholder: "Enter override code",
                            text: $subscriptionOverrideText,
                            dialPadNavigationTitle: "Subscription override"
                        )
                            .onChange(of: subscriptionOverrideText) { new in
                                let digitsOnly = new.filter { $0.isNumber }
                                if digitsOnly != new {
                                    subscriptionOverrideText = digitsOnly
                                }
                                settingsStore.subscriptionOverrideCode = digitsOnly
                            }
                        if settingsStore.isSubscriptionOverrideActive {
                            L10nText("Override is active for this build; subscription checks are bypassed.")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }

                Divider().background(Color.gray.opacity(0.3))

                VStack(alignment: .leading, spacing: 10) {
                    L10nText("TierTap account")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    NavigationLink {
                        TierTapAccountView()
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle")
                            L10nText("TierTap Account")
                                .font(.subheadline.bold())
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6).opacity(0.25))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var favoritesSection: some View {
        SettingsSection(
            title: "Favorites",
            systemImage: "star.fill",
            isExpanded: $isFavoritesExpanded
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    L10nText("Favorite casino games")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    
                    if settingsStore.favoriteGames.isEmpty {
                        L10nText("No favorite games yet. Tap **Add game from picker** to select from the game list.")
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
                            L10nText("Add game from picker")
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
                    L10nText("Favorite slot games")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    if settingsStore.favoriteSlotGames.isEmpty {
                        L10nText("No favorite slots yet. Tap **Add slot from picker** to choose from the slot list.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(settingsStore.favoriteSlotGames, id: \.self) { game in
                                    HStack(spacing: 6) {
                                        Text(game)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Button {
                                            settingsStore.favoriteSlotGames.removeAll { $0 == game }
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
                        slotGamePickerSelection = ""
                        isShowingSlotGamePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            L10nText("Add slot from picker")
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
                    L10nText("Default game type")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    L10nText("Controls whether new sessions and analytics default to table games, slots, or poker.")
                        .font(.caption)
                        .foregroundColor(.gray)
                    GameCategoryWheelPicker(
                        selection: Binding(
                            get: { settingsStore.defaultGameCategory },
                            set: { settingsStore.defaultGameCategory = $0 }
                        ),
                        heading: "",
                        compactHeading: true
                    )
                    .environmentObject(settingsStore)
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                VStack(alignment: .leading, spacing: 8) {
                    L10nText("Common casino locations")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    
                    if settingsStore.favoriteCasinos.isEmpty {
                        L10nText("No favorite locations yet. Tap **Add casino from picker** to select from the casino map/search.")
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
                            L10nText("Add casino from picker")
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

                VStack(alignment: .leading, spacing: 10) {
                    L10nText("Quick amounts")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    L10nText("Common denominations")
                        .font(.caption)
                        .foregroundColor(.gray)
                    HStack(spacing: 8) {
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
                        DialPadLaunchButton {
                            denominationDialPadDraft = ""
                            showDenominationDialPad = true
                        }
                    }
                    .sheet(isPresented: $showDenominationDialPad, onDismiss: {
                        if let v = Int(denominationDialPadDraft), v > 0 {
                            if denominationsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                denominationsText = "\(v)"
                            } else {
                                let trimmed = denominationsText.trimmingCharacters(in: .whitespacesAndNewlines)
                                let sep = trimmed.hasSuffix(",") ? " " : ", "
                                denominationsText = trimmed + sep + "\(v)"
                            }
                        }
                        denominationDialPadDraft = ""
                    }) {
                        NumericDialPadSheet(value: $denominationDialPadDraft, navigationTitle: "Add denomination")
                            .environmentObject(settingsStore)
                    }
                    Toggle("Use \(settingsStore.currencySymbol)18 increment mode", isOn: $settingsStore.useEighteenXMultipliers)
                        .tint(.green)
                    Text("When enabled, quick buttons use each denomination ×18 (e.g. 20 → 360) for \(settingsStore.currencySymbol)18-style bets.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Divider().background(Color.gray.opacity(0.3))

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Casino chimes & haptics", isOn: $settingsStore.enableCasinoFeedback)
                        .tint(.green)
                    L10nText("When on, major actions like check-in, buy-ins, closing out sessions, and sharing will play quick casino-style chimes and success haptics.")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Picker("Sound profile", selection: $settingsStore.soundProfile) {
                        ForEach(SettingsStore.SoundProfile.allCases) { profile in
                            Text(L10n.tr(profile.displayName, language: settingsStore.appLanguage)).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    L10nText("Each profile uses its own set of external casino sound effects (e.g. classic chips, softer chimes, or arcade-style pings).")
                        .font(.caption2)
                        .foregroundColor(.gray)
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
                    L10nText("Presets")
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
                            L10nText("Save current as preset")
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
                    L10nText("Custom colors")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            L10nText("Primary")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            ColorPicker("Primary color", selection: $primaryColorSelection, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: primaryColorSelection) { new in
                                    settingsStore.setPrimaryColor(new)
                                }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            L10nText("Secondary")
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
                            L10nText("Preview")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            L10nText("Primary → Secondary")
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

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    private var dataExportSection: some View {
        SettingsSection(
            title: "Data & Export",
            systemImage: "square.and.arrow.up.on.square",
            isExpanded: $isDataExportExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    L10nText("CSV game type")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    L10nText("Choose whether to export table, slots, or poker sessions. Older sessions without a game type are treated as table games.")
                        .font(.caption)
                        .foregroundColor(.gray)
                    GameCategoryWheelPicker(
                        selection: $exportGameCategory,
                        heading: "CSV scope",
                        compactHeading: true
                    )
                    .environmentObject(settingsStore)
                }

                Button {
                    exportSessionsAsCSV()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        L10nText("Export sessions as CSV")
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

                L10nText("Exports your recorded sessions to a .csv file so you can back up your data or analyze it elsewhere. Uses the iOS Share sheet to send to Files, email, or other apps.")
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
                NavigationLink {
                    UserGuideView()
                        .environmentObject(settingsStore)
                } label: {
                    HStack {
                        Image(systemName: "book.pages.fill")
                        L10nText("User Guide")
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6).opacity(0.25))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                if let gaURL = URL(string: "https://www.gamblersanonymous.org/") {
                    Link(destination: gaURL) {
                        HStack {
                            Image(systemName: "heart.circle.fill")
                            L10nText("If you need help — Gamblers Anonymous")
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
                        L10nText("Privacy")
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
                        L10nText("Sponsor")
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
                        L10nText("EULA")
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
        let allSessions = sessionStore.sessions
        guard !allSessions.isEmpty else { return }

        let sessions = allSessions.filter { session in
            let category = session.gameCategory ?? .table
            return category == exportGameCategory
        }

        guard !sessions.isEmpty else {
            exportErrorMessage = "No sessions for the selected game type are available to export."
            isShowingExportError = true
            return
        }

        isExporting = true

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
            "total_comp",
            "expected_value",
            "ev_per_hour",
            "avg_bet_actual",
            "avg_bet_rated",
            "starting_tier_points",
            "ending_tier_points",
            "tier_points_earned",
            "tiers_per_hour",
            "tiers_per_100_rated_bet_hour",
            "status",
            "game_category",
            "poker_game_kind",
            "poker_allows_rebuy",
            "poker_allows_add_on",
            "poker_has_free_out",
            "poker_variant",
            "poker_small_blind",
            "poker_big_blind",
            "poker_ante",
            "poker_level_minutes",
            "poker_starting_stack"
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
            let totalComp = String(s.totalComp)
            let expectedValue = s.expectedValue.map { String($0) } ?? ""
            let evPerHour = s.expectedValuePerHour.map { String(format: "%.4f", $0) } ?? ""

            let avgBetActual = s.avgBetActual.map { String($0) } ?? ""
            let avgBetRated = s.avgBetRated.map { String($0) } ?? ""

            let startingTier = String(s.startingTierPoints)
            let endingTier = s.endingTierPoints.map { String($0) } ?? ""
            let tierEarned = s.tierPointsEarned.map { String($0) } ?? ""

            let tiersPerHour = s.tiersPerHour.map { String(format: "%.4f", $0) } ?? ""
            let tiersPerHundred = s.tiersPerHundredRatedBetHour.map { String(format: "%.4f", $0) } ?? ""

            let gameCategory = (s.gameCategory ?? .table).rawValue
            let pokerGameKind = s.pokerGameKind?.rawValue ?? ""
            let pokerAllowsRebuy = s.pokerAllowsRebuy.map { $0 ? "true" : "false" } ?? ""
            let pokerAllowsAddOn = s.pokerAllowsAddOn.map { $0 ? "true" : "false" } ?? ""
            let pokerHasFreeOut = s.pokerHasFreeOut.map { $0 ? "true" : "false" } ?? ""
            let pokerVariant = s.pokerVariant ?? ""
            let pokerSmallBlind = s.pokerSmallBlind.map { String($0) } ?? ""
            let pokerBigBlind = s.pokerBigBlind.map { String($0) } ?? ""
            let pokerAnte = s.pokerAnte.map { String($0) } ?? ""
            let pokerLevelMinutes = s.pokerLevelMinutes.map { String($0) } ?? ""
            let pokerStartingStack = s.pokerStartingStack.map { String($0) } ?? ""

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
                totalComp,
                expectedValue,
                evPerHour,
                avgBetActual,
                avgBetRated,
                startingTier,
                endingTier,
                tierEarned,
                tiersPerHour,
                tiersPerHundred,
                s.status.rawValue,
                gameCategory,
                pokerGameKind,
                pokerAllowsRebuy,
                pokerAllowsAddOn,
                pokerHasFreeOut,
                pokerVariant,
                pokerSmallBlind,
                pokerBigBlind,
                pokerAnte,
                pokerLevelMinutes,
                pokerStartingStack
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
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Label {
                        Text(L10n.tr(title, language: appLanguage))
                    } icon: {
                        Image(systemName: systemImage)
                    }
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
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

