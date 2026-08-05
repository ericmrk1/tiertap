import SwiftUI
import UIKit

#if os(iOS)

/// One-tap session share: last style + auto underlay + privacy preset (WP-S1 / S3 / S4).
struct SessionArtQuickShareSheet: View {
    let sessionId: UUID
    var onCustomize: () -> Void
    var onShareText: () -> Void

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var privacy: SessionArtPrivacyPreset = SessionArtSharePresetStore.lastPrivacyPreset
    @State private var aspect: SessionArtAspectRatio = SessionArtSharePresetStore.lastAspectRatio
    @State private var previewImage: UIImage?
    @State private var isRendering = false
    @State private var shareItem: SessionArtShareMediaItem?
    @State private var statusMessage: String?
    @State private var showSystemShare = false

    private var session: Session? {
        if let saved = store.sessions.first(where: { $0.id == sessionId }) { return saved }
        if store.liveSession?.id == sessionId { return store.liveSession }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 420)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        } else if isRendering {
                            ProgressView("Preparing share…")
                                .tint(.white)
                                .foregroundColor(.white)
                                .padding(.vertical, 60)
                        } else {
                            Text("Couldn’t build a preview.")
                                .foregroundColor(.orange)
                                .padding(.vertical, 40)
                        }

                        privacyPicker
                        aspectPicker

                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Button {
                                    shareNow()
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.red)
                                        .foregroundStyle(.white)
                                        .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                                .disabled(previewImage == nil)

                                Button {
                                    saveToPhotos()
                                } label: {
                                    Label("Save", systemImage: "square.and.arrow.down")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.18))
                                        .foregroundStyle(.white)
                                        .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                                .disabled(previewImage == nil)
                            }

                            Button {
                                shareStoryAndFeed()
                            } label: {
                                Label("Share Story + Feed", systemImage: "rectangle.stack")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.indigo.opacity(0.85))
                                    .foregroundStyle(.white)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .disabled(session == nil || isRendering)

                            if InstagramStoriesSharer.isAvailable {
                                Button {
                                    shareToInstagram()
                                } label: {
                                    Label("Instagram Stories", systemImage: "camera.filters")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.purple.opacity(0.85))
                                        .foregroundStyle(.white)
                                        .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                                .disabled(previewImage == nil)
                            }

                            Button {
                                onCustomize()
                            } label: {
                                Label("Customize editor", systemImage: "slider.horizontal.3")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.blue.opacity(0.75))
                                    .foregroundStyle(.white)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)

                            Button {
                                onShareText()
                            } label: {
                                Label("Share text story", systemImage: "text.alignleft")
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Quick Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.green)
                }
            }
            .onAppear { refreshPreview() }
            .onChange(of: privacy) { _ in
                SessionArtSharePresetStore.lastPrivacyPreset = privacy
                refreshPreview()
            }
            .onChange(of: aspect) { _ in
                SessionArtSharePresetStore.lastAspectRatio = aspect
                refreshPreview()
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.activityItems)
            }
        }
    }

    private var privacyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.7))
            Picker("", selection: $privacy) {
                ForEach(SessionArtPrivacyPreset.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.segmented)
            Text(privacy.subtitle)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.65))
        }
    }

    private var aspectPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.7))
            Picker("", selection: $aspect) {
                ForEach(SessionArtAspectRatio.allCases) { a in
                    Text(a.title).tag(a)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func refreshPreview() {
        guard let session else {
            previewImage = nil
            return
        }
        isRendering = true
        let currency = settingsStore.currencySymbol
        let privacy = privacy
        let aspect = aspect
        DispatchQueue.global(qos: .userInitiated).async {
            let image = SessionArtQuickShareRenderer.render(
                session: session,
                currencySymbol: currency,
                privacy: privacy,
                aspect: aspect
            )
            DispatchQueue.main.async {
                previewImage = image
                isRendering = false
            }
        }
    }

    private func shareNow() {
        guard let previewImage else { return }
        shareItem = SessionArtShareMediaItem(activityItems: [previewImage])
    }

    private func shareStoryAndFeed() {
        guard let session else { return }
        isRendering = true
        statusMessage = nil
        let currency = settingsStore.currencySymbol
        let privacy = privacy
        let aspect = aspect
        DispatchQueue.global(qos: .userInitiated).async {
            let story = SessionArtQuickShareRenderer.render(
                session: session,
                currencySymbol: currency,
                privacy: privacy,
                aspect: .story
            )
            let feed = SessionArtQuickShareRenderer.render(
                session: session,
                currencySymbol: currency,
                privacy: privacy,
                aspect: .feed
            )
            DispatchQueue.main.async {
                isRendering = false
                shareItem = SessionArtShareMediaItem(activityItems: [story, feed])
                statusMessage = "Story + Feed ready."
            }
        }
    }

    private func shareToInstagram() {
        guard let previewImage else { return }
        InstagramStoriesSharer.shareImage(previewImage) { ok in
            if !ok {
                shareItem = SessionArtShareMediaItem(activityItems: [previewImage])
                statusMessage = "Instagram unavailable — opened system share."
            }
        }
    }

    private func saveToPhotos() {
        guard let previewImage else { return }
        SessionArtPhotoLibrarySaver.saveImage(previewImage) { ok in
            statusMessage = ok ? "Saved to Photos." : "Couldn't save to Photos."
        }
    }
}

/// Local share wrapper so Quick Share can pass multiple activity items (WP-X5).
private struct SessionArtShareMediaItem: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}

#endif
