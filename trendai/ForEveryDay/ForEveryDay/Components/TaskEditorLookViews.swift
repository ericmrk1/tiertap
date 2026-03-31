import PhotosUI
import SwiftUI
import UIKit

// MARK: - Icon kind (editor)

enum TaskEditorIconKind: String, CaseIterable, Identifiable {
    case none
    case emoji
    case systemSymbol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .emoji: return "Emoji"
        case .systemSymbol: return "SF Symbol"
        }
    }
}

// MARK: - Photo hero (top of editor)

struct TaskEditorPhotoHero: View {
    let attachmentImageData: Data?
    var onTapImage: () -> Void

    var body: some View {
        Group {
            if let data = attachmentImageData, let ui = UIImage(data: data) {
                Button(action: onTapImage) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View photo full screen")
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text("No photo yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }
}

// MARK: - Emoji palette

private enum TaskEmojiPalette {
    static let symbols: [String] = [
        "😀", "😃", "😄", "😁", "😅", "🤣", "😂", "🙂", "😊", "😇",
        "🥰", "😍", "🤩", "😘", "😋", "😛", "🤪", "🧐", "😎", "🥳",
        "😕", "😟", "🙁", "😮", "😲", "🥺", "😢", "😭", "😤", "😡",
        "🤔", "🤫", "🤗", "🤝", "👍", "👎", "👏", "🙏", "💪", "✌️",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "💔", "✨", "🔥",
        "⭐", "🌙", "☀️", "🌈", "☁️", "❄️", "💧", "🌿", "🌸", "🍀",
        "🎯", "🏆", "🎉", "🎁", "🎵", "📚", "✏️", "💡", "📌", "⏰",
        "☕", "🍎", "🥗", "🍕", "🥤", "🏃", "🚴", "🧘", "🛏️", "🐶",
        "🐱", "🦊", "🐻", "🦁", "🐸", "🐝", "🦋", "🌊", "🏔️", "🚀",
    ]
}

// MARK: - Look section (icon + photo actions)

struct TaskLookEditorSection: View {
    @Binding var iconKind: TaskEditorIconKind
    @Binding var selectedEmoji: String?
    @Binding var systemSymbolName: String?
    @Binding var attachmentImageData: Data?
    @Binding var photoPickerItem: PhotosPickerItem?
    @Binding var showSymbolPicker: Bool
    let isDisabled: Bool

    private let emojiColumns = [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 8)]

    var body: some View {
        Section {
            Picker("Icon", selection: $iconKind) {
                ForEach(TaskEditorIconKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isDisabled)
            .onChange(of: iconKind) { _, newValue in
                switch newValue {
                case .none:
                    selectedEmoji = nil
                    systemSymbolName = nil
                case .emoji:
                    systemSymbolName = nil
                case .systemSymbol:
                    selectedEmoji = nil
                }
            }

            switch iconKind {
            case .none:
                EmptyView()
            case .emoji:
                LazyVGrid(columns: emojiColumns, spacing: 10) {
                    ForEach(TaskEmojiPalette.symbols, id: \.self) { em in
                        Button {
                            selectedEmoji = em
                            HapticButton.lightImpact()
                        } label: {
                            Text(em)
                                .font(.system(size: 28))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selectedEmoji == em ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .disabled(isDisabled)

                if selectedEmoji != nil {
                    Button("Clear emoji", role: .destructive) {
                        selectedEmoji = nil
                    }
                    .disabled(isDisabled)
                }
            case .systemSymbol:
                HStack(spacing: 12) {
                    if let s = systemSymbolName, UIImage(systemName: s) != nil {
                        Image(systemName: s)
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "square.grid.3x3.square")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(systemSymbolName ?? "None selected")
                            .font(.subheadline.monospaced())
                            .lineLimit(2)
                            .foregroundStyle(systemSymbolName == nil ? .secondary : .primary)
                    }
                    Spacer(minLength: 0)
                    Button("Browse") {
                        showSymbolPicker = true
                        HapticButton.lightImpact()
                    }
                    .disabled(isDisabled)
                }
                if systemSymbolName != nil {
                    Button("Clear symbol", role: .destructive) {
                        systemSymbolName = nil
                    }
                    .disabled(isDisabled)
                }
            }

            PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                Label(attachmentImageData == nil ? "Choose photo" : "Replace photo", systemImage: "photo")
            }
            .disabled(isDisabled)

            if attachmentImageData != nil {
                Button(role: .destructive) {
                    attachmentImageData = nil
                    photoPickerItem = nil
                } label: {
                    Label("Remove photo", systemImage: "trash")
                }
                .disabled(isDisabled)
            }
        } header: {
            Text("Look")
        } footer: {
            Text("Pick a list icon (emoji or SF Symbol), optional photo at the top, or both. Tap the photo preview for full screen.")
        }
    }
}

// MARK: - SF Symbol picker

struct SystemSymbolPickerSheet: View {
    @Binding var selectedName: String?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var allNames: [String] { SFSymbolCatalog.validatedNames }

    private var filteredNames: [String] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return [] }
        return allNames.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    suggestedList
                    hintRow
                } else if filteredNames.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    ForEach(filteredNames, id: \.self) { name in
                        symbolRow(name)
                    }
                }
            }
            .navigationTitle("SF Symbols")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search symbol names")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticButton.lightImpact()
                        dismiss()
                    }
                }
            }
        }
    }

    private var suggestedList: some View {
        Section("Suggested") {
            ForEach(SFSymbolCatalog.suggestedSymbols, id: \.self) { name in
                symbolRow(name)
            }
        }
    }

    private var hintRow: some View {
        Section {
            Text("Search by name (e.g. star, heart, leaf). Names match Apple’s SF Symbols set on this OS.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func symbolRow(_ name: String) -> some View {
        Button {
            selectedName = name
            HapticButton.lightImpact()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: name)
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 28, height: 28)
                Text(name)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if selectedName == name {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
