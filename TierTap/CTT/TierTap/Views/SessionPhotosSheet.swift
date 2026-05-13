import SwiftUI
import UIKit

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
        _ = store.addAttachedSessionPhoto(sessionID: sessionID, image: image)
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
                }
            }
        }
    }
}