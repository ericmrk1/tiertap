import SwiftUI

/// Sprint 2: one-tap wallet tier-goal setup from program ladders (MGM / Caesars / etc.).
struct LoyaltyProgramLadderPicker: View {
    @Binding var rewardProgram: String
    @Binding var tierGoalPointsText: String
    @Binding var tierGoalLabel: String

    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var showLadderSheet = false

    private var selectedPoints: Int? {
        Int(tierGoalPointsText.filter(\.isNumber))
    }

    private var hasGoal: Bool {
        (selectedPoints ?? 0) > 0 || !tierGoalLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var matchingLadder: TierTapProductEnhancements.ProgramLadder? {
        TierTapProductEnhancements.resolvedLadder(
            matchingProgram: rewardProgram,
            customEntries: settingsStore.customLadderTiers
        )
    }

    private var selectedStep: TierTapProductEnhancements.LadderTierStep? {
        guard let ladder = matchingLadder, let pts = selectedPoints else { return nil }
        if let byPoints = ladder.tiers.first(where: { $0.points == pts }) { return byPoints }
        let label = tierGoalLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        return ladder.tiers.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }
    }

    var body: some View {
        if TierTapProductEnhancements.isSprint2Active {
            VStack(alignment: .leading, spacing: 10) {
                if hasGoal {
                    goalSummary
                }

                Button {
                    showLadderSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.body.weight(.semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hasGoal ? "Change ladder goal" : "Set goal from ladder")
                                .font(.subheadline.weight(.semibold))
                            Text(hasGoal
                                 ? "Pick another status threshold in one tap"
                                 : "MGM, Caesars, Wynn… tap a tier — done")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                if let ladder = matchingLadder, !hasGoal {
                    Text("Quick pick · \(shortProgramName(ladder.programName))")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                    quickTierRow(ladder: ladder)
                }

                if hasGoal {
                    Button(role: .destructive) {
                        clearGoal()
                    } label: {
                        Text("Clear tier goal")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showLadderSheet) {
                LadderGoalPickerSheet(
                    initialProgramName: matchingLadder?.programName
                        ?? rewardProgram.trimmingCharacters(in: .whitespacesAndNewlines),
                    onPick: { program, step in
                        apply(program: program, step: step)
                        showLadderSheet = false
                    },
                    onCancel: { showLadderSheet = false }
                )
                .environmentObject(settingsStore)
            }
        }
    }

    private var goalSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "target")
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tier goal")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(summaryTitle)
                    .font(.subheadline.weight(.semibold))
                if let pts = selectedPoints, pts > 0 {
                    Text(formattedPoints(pts))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private var summaryTitle: String {
        let label = tierGoalLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let step = selectedStep {
            return step.label
        }
        if !label.isEmpty { return label }
        return "Custom goal"
    }

    private func quickTierRow(ladder: TierTapProductEnhancements.ProgramLadder) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ladder.tiers) { step in
                    Button {
                        apply(program: ladder.programName, step: step)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.label)
                                .font(.caption.weight(.semibold))
                            Text(formattedPoints(step.points))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.green.opacity(0.45), lineWidth: 1)
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func apply(program: String, step: TierTapProductEnhancements.LadderTierStep) {
        if rewardProgram.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || TierTapProductEnhancements.resolvedLadder(
                matchingProgram: rewardProgram,
                customEntries: settingsStore.customLadderTiers
            )?.programName != program {
            rewardProgram = program
        }
        tierGoalPointsText = "\(step.points)"
        tierGoalLabel = step.label
    }

    private func clearGoal() {
        tierGoalPointsText = ""
        tierGoalLabel = ""
    }

    private func shortProgramName(_ name: String) -> String {
        name
            .replacingOccurrences(of: " Rewards", with: "")
            .replacingOccurrences(of: "Rewards", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formattedPoints(_ points: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: points)) ?? "\(points)") + " pts"
    }
}

// MARK: - Full ladder sheet

private struct LadderGoalPickerSheet: View {
    let initialProgramName: String
    var onPick: (String, TierTapProductEnhancements.LadderTierStep) -> Void
    var onCancel: () -> Void

    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var selectedProgramName: String
    @State private var showAddCustomEntry = false

    init(
        initialProgramName: String,
        onPick: @escaping (String, TierTapProductEnhancements.LadderTierStep) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialProgramName = initialProgramName
        self.onPick = onPick
        self.onCancel = onCancel
        let trimmed = initialProgramName.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = TierTapProductEnhancements.ladder(matchingProgram: trimmed)?.programName
            ?? (trimmed.isEmpty ? nil : trimmed)
            ?? TierTapProductEnhancements.programLadders.first?.programName
            ?? ""
        _selectedProgramName = State(initialValue: match)
    }

    private var programNames: [String] {
        TierTapProductEnhancements.availableLadderProgramNames(
            customEntries: settingsStore.customLadderTiers,
            extraProgramNames: settingsStore.customRewardPrograms + [initialProgramName, selectedProgramName]
        )
    }

    private var selectedLadder: TierTapProductEnhancements.ProgramLadder {
        TierTapProductEnhancements.resolvedLadder(
            matchingProgram: selectedProgramName,
            customEntries: settingsStore.customLadderTiers
        ) ?? TierTapProductEnhancements.ProgramLadder(programName: selectedProgramName, tiers: [])
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Program", selection: $selectedProgramName) {
                        ForEach(programNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.green)
                    .foregroundStyle(.green)
                } header: {
                    Text("Loyalty program")
                } footer: {
                    Text("Choose a program, then tap the status you’re chasing — or add your own custom status.")
                }

                Section {
                    if selectedLadder.tiers.isEmpty {
                        Text("No statuses yet. Add a custom status below.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(selectedLadder.tiers) { step in
                            Button {
                                onPick(selectedLadder.programName, step)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(step.label)
                                                .font(.body.weight(.semibold))
                                                .foregroundColor(.primary)
                                            if step.isCustom {
                                                Text("Custom")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.14))
                                                    .cornerRadius(6)
                                            }
                                        }
                                        Text(formattedPoints(step.points) + " tier credits")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.green)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if step.isCustom, let customID = step.customID {
                                    Button(role: .destructive) {
                                        settingsStore.removeCustomLadderTier(id: customID)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        showAddCustomEntry = true
                    } label: {
                        Label("Add custom status", systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                } header: {
                    Text("Tap your next status")
                }
            }
            .navigationTitle("Ladder goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .sheet(isPresented: $showAddCustomEntry) {
                AddCustomLadderEntrySheet(programName: selectedProgramName) { label, points in
                    let ok = settingsStore.addCustomLadderTier(
                        programName: selectedProgramName,
                        label: label,
                        points: points
                    )
                    if ok {
                        // Keep picker on the program that received the new entry.
                        if let canonical = TierTapProductEnhancements.ladder(matchingProgram: selectedProgramName)?.programName {
                            selectedProgramName = canonical
                        }
                    }
                    return ok
                }
                .environmentObject(settingsStore)
            }
        }
    }

    private func formattedPoints(_ points: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: points)) ?? "\(points)"
    }
}

// MARK: - Add custom ladder entry

private struct AddCustomLadderEntrySheet: View {
    let programName: String
    /// Returns `true` when the entry was saved.
    var onSave: (String, Int) -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var labelText = ""
    @State private var pointsText = ""
    @State private var showDuplicateAlert = false

    private var trimmedLabel: String {
        labelText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedPoints: Int? {
        let digits = pointsText.filter(\.isNumber)
        guard !digits.isEmpty, let n = Int(digits), n > 0 else { return nil }
        return n
    }

    private var canSave: Bool {
        !trimmedLabel.isEmpty && parsedPoints != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(programName)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Program")
                }

                Section {
                    TextField("Status name (e.g. NOIR)", text: $labelText)
                        .textInputAutocapitalization(.words)
                    NumericEntryWithDialPad(
                        placeholder: "Points threshold",
                        text: $pointsText,
                        dialPadNavigationTitle: "Points threshold"
                    )
                } header: {
                    Text("Custom status")
                } footer: {
                    Text("Saved to this program’s ladder so you can reuse it anytime.")
                }
            }
            .navigationTitle("Add status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let points = parsedPoints else { return }
                        if onSave(trimmedLabel, points) {
                            dismiss()
                        } else {
                            showDuplicateAlert = true
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .alert("Already on this ladder", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A status with this name or points threshold already exists for \(programName).")
            }
        }
    }
}
