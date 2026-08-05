import SwiftUI
import UIKit

// MARK: - Photo context tags

struct SessionPhotoContextTagPicker: View {
    @Binding var selectedTags: Set<SessionPhotoContextTag>
    @Binding var customLabels: [String]
    var caption: LocalizedStringKey = "Photo context"
    var onContextChanged: (() -> Void)? = nil

    @State private var customDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.caption.bold())
                .foregroundColor(.gray)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(SessionPhotoContextTag.pickerCases, id: \.self) { tag in
                    let isSelected = selectedTags.contains(tag)
                    Button {
                        if isSelected {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                        notifyChange()
                    } label: {
                        Text(tag.label)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? Color.green : Color.white.opacity(0.18))
                            .foregroundColor(isSelected ? .black : .white)
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(customLabels, id: \.self) { label in
                    Button {
                        customLabels.removeAll { $0 == label }
                        notifyChange()
                    } label: {
                        HStack(spacing: 4) {
                            Text(label)
                            Image(systemName: "xmark")
                                .font(.caption2.bold())
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.black)
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("Add your own…", text: $customDraft)
                    .textFieldStyle(DarkTextFieldStyle())
                    .submitLabel(.done)
                    .onSubmit { addCustomLabel() }
                Button("Add") { addCustomLabel() }
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .opacity(customDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    .cornerRadius(10)
                    .disabled(customDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addCustomLabel() {
        let trimmed = customDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = trimmed.lowercased()
        let duplicatePreset = SessionPhotoContextTag.pickerCases.contains { $0.label.lowercased() == key }
        let duplicateCustom = customLabels.contains { $0.lowercased() == key }
        guard !duplicatePreset, !duplicateCustom else {
            customDraft = ""
            return
        }
        customLabels.append(trimmed)
        customDraft = ""
        notifyChange()
    }

    private func notifyChange() {
        onContextChanged?()
    }
}

struct SessionPhotoContextTagBadgeRow: View {
    let tags: [SessionPhotoContextTag]
    var customLabels: [String] = []

    var body: some View {
        let labels = tags.map(\.label) + customLabels
        if !labels.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.16))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

enum SessionPhotosSheetMode {
    case manage
    case selectPrimary
}

struct SessionPhotosEntryButton: View {
    let action: () -> Void
    var compact: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 5 : 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                L10nText("Photos")
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 6 : 8)
            .background(Color.black)
            .cornerRadius(compact ? 8 : 10)
        }
        .accessibilityLabel("Session photos")
    }
}

struct SessionPhotosSheet: View {
    let sessionID: UUID
    var mode: SessionPhotosSheetMode = .manage

    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var photoSource: SessionPhotoPickerSource?
    @State private var previewRef: SessionPhotoRef?
    @State private var pendingPhotoContextTags: Set<SessionPhotoContextTag> = []
    @State private var pendingCustomContextLabels: [String] = []

    private enum SessionPhotoPickerSource: Identifiable {
        case camera
        case photoLibrary

        var id: String {
            switch self {
            case .camera: return "camera"
            case .photoLibrary: return "photoLibrary"
            }
        }
    }

    private var session: Session? {
        if let live = store.liveSession, live.id == sessionID { return live }
        return store.sessions.first(where: { $0.id == sessionID })
    }

    private var items: [SessionPhotoCatalog.Item] {
        guard let session else { return [] }
        return SessionPhotoCatalog.items(for: session)
    }

    private var primaryRef: SessionPhotoRef? {
        guard let session else { return nil }
        return SessionPhotoCatalog.resolvedPrimaryRef(for: session)
    }

    private var canManageAttachments: Bool {
        mode == .manage
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if items.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 34))
                                    .foregroundColor(.gray)
                                L10nText("No session photos yet.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                if canManageAttachments {
                                    L10nText("Add photos from the camera or photo library.")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 12)], spacing: 12) {
                                ForEach(items) { item in
                                    sessionPhotoTile(item)
                                }
                            }
                        }

                        if canManageAttachments {
                            HStack(spacing: 12) {
                                Button {
                                    photoSource = .camera
                                } label: {
                                    LocalizedLabel(title: "Camera", systemImage: "camera")
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.black)
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                }

                                Button {
                                    photoSource = .photoLibrary
                                } label: {
                                    LocalizedLabel(title: "Photo Library", systemImage: "photo")
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.black)
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                }
                            }

                            SessionPhotoContextTagPicker(
                                selectedTags: $pendingPhotoContextTags,
                                customLabels: $pendingCustomContextLabels
                            )
                        }
                    }
                    .padding()
                }
            }
            .localizedNavigationTitle("Session Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.green)
                }
            }
            .adaptiveSheet(item: $photoSource) { source in
                switch source {
                case .camera:
                    CameraPicker(selectedImage: .constant(nil)) { image in
                        handlePickedPhoto(image)
                    }
                case .photoLibrary:
                    ImagePicker(selectedImage: .constant(nil)) { image in
                        handlePickedPhoto(image)
                    }
                }
            }
            .adaptiveSheet(item: $previewRef) { ref in
                SessionPhotoPreviewSheet(sessionID: sessionID, ref: ref, mode: mode)
                    .environmentObject(store)
                    .environmentObject(settingsStore)
            }
        }
    }

    @ViewBuilder
    private func sessionPhotoTile(_ item: SessionPhotoCatalog.Item) -> some View {
        let isPrimary = primaryRef == item.ref
        Button {
            previewRef = item.ref
        } label: {
            ZStack(alignment: .topLeading) {
                Group {
                    if let session, let image = SessionPhotoCatalog.image(for: item.ref, session: session) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.systemGray6).opacity(0.35)
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipped()
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isPrimary ? Color.green : Color.white.opacity(0.2), lineWidth: isPrimary ? 2 : 1)
                )

                VStack(alignment: .leading, spacing: 0) {
                    if isPrimary {
                        Text("Primary")
                            .font(.caption2.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(8)
                            .padding(6)
                    }
                    if !item.contextTags.isEmpty || !item.customContextLabels.isEmpty {
                        SessionPhotoContextTagBadgeRow(tags: item.contextTags, customLabels: item.customContextLabels)
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                store.setPrimarySessionPhoto(sessionID: sessionID, ref: item.ref)
            } label: {
                Label("Set as primary", systemImage: "star.fill")
            }
            if canManageAttachments, item.ref.kind != .comp {
                Button(role: .destructive) {
                    store.removeSessionPhoto(sessionID: sessionID, ref: item.ref)
                } label: {
                    Label("Remove photo", systemImage: "trash")
                }
            }
        }
    }

    private func handlePickedPhoto(_ image: UIImage) {
        guard canManageAttachments else { return }
        _ = store.addAttachedSessionPhoto(
            sessionID: sessionID,
            image: image,
            contextTags: pendingPhotoContextTags,
            customContextLabels: pendingCustomContextLabels
        )
        pendingPhotoContextTags = []
        pendingCustomContextLabels = []
    }
}

struct SessionPhotosPrimarySelector: View {
    let session: Session
    let onOpenGallery: () -> Void

    @EnvironmentObject var store: SessionStore

    private var items: [SessionPhotoCatalog.Item] {
        SessionPhotoCatalog.items(for: session)
    }

    private var primaryRef: SessionPhotoRef? {
        SessionPhotoCatalog.resolvedPrimaryRef(for: session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let primaryRef,
               let image = SessionPhotoCatalog.image(for: primaryRef, session: session) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.8), lineWidth: 2)
                    )
                Text("Primary photo")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        let isPrimary = primaryRef == item.ref
                        Button {
                            store.setPrimarySessionPhoto(sessionID: session.id, ref: item.ref)
                        } label: {
                            Group {
                                if let image = SessionPhotoCatalog.image(for: item.ref, session: session) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Color(.systemGray6).opacity(0.35)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipped()
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isPrimary ? Color.green : Color.white.opacity(0.2), lineWidth: isPrimary ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            SessionPhotosEntryButton(action: onOpenGallery)
        }
    }
}

private struct SessionPhotoPreviewSheet: View {
    let sessionID: UUID
    let ref: SessionPhotoRef
    let mode: SessionPhotosSheetMode

    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var editableContextTags: Set<SessionPhotoContextTag> = []
    @State private var editableCustomLabels: [String] = []

    private var session: Session? {
        if let live = store.liveSession, live.id == sessionID { return live }
        return store.sessions.first(where: { $0.id == sessionID })
    }

    private var item: SessionPhotoCatalog.Item? {
        guard let session else { return nil }
        return SessionPhotoCatalog.items(for: session).first(where: { $0.ref == ref })
    }

    private var isPrimary: Bool {
        guard let session else { return false }
        return SessionPhotoCatalog.resolvedPrimaryRef(for: session) == ref
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let session,
                           let image = SessionPhotoCatalog.image(for: ref, session: session) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }

                        if let item {
                            Text(item.title)
                                .font(.headline)
                                .foregroundColor(.white)
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }

                        if mode == .manage {
                            if !editableContextTags.isEmpty || !editableCustomLabels.isEmpty {
                                SessionPhotoContextTagBadgeRow(
                                    tags: SessionPhotoContextTag.sorted(editableContextTags),
                                    customLabels: editableCustomLabels
                                )
                            }
                        } else if let item, !item.contextTags.isEmpty || !item.customContextLabels.isEmpty {
                            SessionPhotoContextTagBadgeRow(
                                tags: item.contextTags,
                                customLabels: item.customContextLabels
                            )
                        }

                        if mode == .manage {
                            SessionPhotoContextTagPicker(
                                selectedTags: $editableContextTags,
                                customLabels: $editableCustomLabels,
                                caption: "Photo context",
                                onContextChanged: persistPhotoContext
                            )
                        }

                        if !isPrimary {
                            Button {
                                store.setPrimarySessionPhoto(sessionID: sessionID, ref: ref)
                            } label: {
                                LocalizedLabel(title: "Set as primary", systemImage: "star.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.black)
                                    .foregroundColor(.white)
                                    .cornerRadius(14)
                            }
                        }

                        if mode == .manage, ref.kind != .comp {
                            Button(role: .destructive) {
                                store.removeSessionPhoto(sessionID: sessionID, ref: ref)
                                dismiss()
                            } label: {
                                LocalizedLabel(title: "Remove photo", systemImage: "trash")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red.opacity(0.2))
                                    .foregroundColor(.red)
                                    .cornerRadius(14)
                            }
                        }
                    }
                    .padding()
                }
            }
            .localizedNavigationTitle("Session photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.green)
                }
            }
            .onAppear { syncContextTagsFromSession() }
        }
    }

    private func syncContextTagsFromSession() {
        guard let session else { return }
        editableContextTags = Set(session.contextTags(for: ref))
        editableCustomLabels = session.customContextLabels(for: ref)
    }

    private func persistPhotoContext() {
        store.setSessionPhotoContext(
            sessionID: sessionID,
            ref: ref,
            tags: SessionPhotoContextTag.sorted(editableContextTags),
            customLabels: editableCustomLabels
        )
    }
}