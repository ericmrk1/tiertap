import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
/// Uniform scale for wallet card photos (deck, detail sheet, add/edit forms).
private let walletCardImageSizeMultiplier: CGFloat = 1.2

private enum WalletHeroImageLayout {
    /// Large hero image when viewing a single card (detail / add / edit), not deck scrolling.
    static var maxHeight: CGFloat {
        min(560, UIScreen.main.bounds.height * 0.48) * walletCardImageSizeMultiplier
    }
}

/// Apple Wallet–inspired stack of reward cards with photo capture, edit/delete, and share-as-image.
struct TierTapWalletView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var walletStore: RewardWalletStore
    @Environment(\.dismiss) private var dismiss

    /// When non-`nil`, the wallet is shown for choosing a card (check-in): swipe the deck, then confirm with **Use this card**.
    var rewardsSelectionHandler: ((RewardWalletCard) -> Void)? = nil
    /// When opening from close-out (or elsewhere), bring this card to the front of the deck if it exists.
    var initialFocusedCardId: UUID? = nil

    @State private var selectedIndex: Int = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var importedImageForNewCard: UIImage?
    @State private var showNewCardSheet = false
    @State private var cardToEdit: RewardWalletCard?
    @State private var showShareSheet = false
    @State private var showShareOptionsSheet = false
    @State private var shareURL: URL?
    @State private var includeTierHistoryInShare = false
    @State private var historyOverlayCardID: UUID?
    @State private var cardForDetail: RewardWalletCard?
    @GestureState private var dragGestureTranslation: CGFloat = 0
    /// `false` = single enlarged card with metadata on the card; `true` = stacked deck + bottom chrome (check-in selection always uses stack).
    @State private var walletStackCollapsed: Bool = true
    /// Small 3D pulse applied to the focused card when stepping through the deck.
    @State private var cardSelectionPulse: Double = 0

    private var cards: [RewardWalletCard] { walletStore.cards }

    /// Stacked deck layout (smaller photos + bottom title/tool row).
    private var useCollapsedDeckLayout: Bool {
        walletStackCollapsed || rewardsSelectionHandler != nil
    }

    /// Large single-card layout with overlay details (browse only).
    private var useExpandedSingleCardLayout: Bool {
        rewardsSelectionHandler == nil && !walletStackCollapsed
    }

    private var safeSelectedIndex: Int {
        guard !cards.isEmpty else { return 0 }
        return min(max(0, selectedIndex), cards.count - 1)
    }

    private func applyInitialWalletSelection() {
        guard !cards.isEmpty else {
            selectedIndex = 0
            return
        }
        if let id = initialFocusedCardId,
           let idx = cards.firstIndex(where: { $0.id == id }) {
            selectedIndex = idx
        } else {
            selectedIndex = max(0, cards.count - 1)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                walletBackground
                if cards.isEmpty {
                    emptyState
                } else {
                    walletStackWithChrome
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("TierTap Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
                if !cards.isEmpty, rewardsSelectionHandler == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                                    walletStackCollapsed.toggle()
                                }
                            } label: {
                                Label(walletStackCollapsed ? "Card" : "Stack", systemImage: walletStackCollapsed ? "rectangle.fill" : "square.stack.3d.up.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.14))
                                    .clipShape(Capsule())
                                    .foregroundColor(.cyan)
                            }
                            .accessibilityLabel(walletStackCollapsed ? "Show single card view" : "Show stacked card view")

                            Button {
                                showShareOptionsSheet = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.cyan)
                            }
                            .accessibilityLabel("Share card")
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !cards.isEmpty, useCollapsedDeckLayout {
                addCardFloatingButton
                    .padding(.bottom, walletBottomChromeHeight + 16)
            }
        }
        .onAppear {
            applyInitialWalletSelection()
            walletStore.preloadAllCardImages()
        }
        .onChange(of: cards.count) { _ in
            selectedIndex = min(selectedIndex, max(0, cards.count - 1))
            walletStore.preloadAllCardImages()
        }
        .onChange(of: initialFocusedCardId) { _ in
            applyInitialWalletSelection()
        }
        .onChange(of: selectedIndex) { _ in
            animateCardSelectionPulse()
        }
        .sheet(isPresented: $showCamera) {
            ProfilePhotoCaptureView(
                image: $importedImageForNewCard,
                preferredSourceType: .camera,
                onFinishedPicking: { _ in schedulePresentNewCardEditor() }
            )
        }
        .sheet(isPresented: $showLibrary) {
            ImagePicker(selectedImage: $importedImageForNewCard, onImagePicked: { _ in
                schedulePresentNewCardEditor()
            })
        }
        .sheet(isPresented: $showNewCardSheet, onDismiss: {
            importedImageForNewCard = nil
        }) {
            if let img = importedImageForNewCard {
                NewWalletCardSheet(initialImage: img, onSaved: {
                    selectedIndex = max(0, walletStore.cards.count - 1)
                    walletStore.preloadAllCardImages()
                })
                .environmentObject(walletStore)
                .environmentObject(settingsStore)
            }
        }
        .sheet(item: $cardToEdit) { card in
            EditWalletCardSheet(card: card) {
                cardToEdit = nil
                walletStore.preloadAllCardImages()
            }
            .environmentObject(walletStore)
            .environmentObject(settingsStore)
        }
        .sheet(item: $cardForDetail) { card in
            WalletCardDetailSheet(card: card)
                .environmentObject(walletStore)
        }
        .adaptiveSheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showShareOptionsSheet) {
            WalletShareOptionsSheet(includeTierHistoryOverlay: $includeTierHistoryInShare) {
                shareFrontCard(includeTierHistoryOverlay: includeTierHistoryInShare)
            }
            .presentationDetents([.height(250)])
        }
        .onChange(of: showShareSheet) { open in
            if !open, let url = shareURL {
                try? FileManager.default.removeItem(at: url)
                shareURL = nil
            }
        }
    }

    /// Presents the metadata sheet after the picker has written `importedImageForNewCard` (avoids racing sheet dismissal vs. binding updates).
    private func schedulePresentNewCardEditor() {
        guard importedImageForNewCard != nil else { return }
        guard !showNewCardSheet else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard importedImageForNewCard != nil, !showNewCardSheet else { return }
            showNewCardSheet = true
        }
    }

    private func card(at index: Int) -> RewardWalletCard? {
        guard index >= 0 && index < cards.count else { return nil }
        return cards[index]
    }

    private var walletBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.12, green: 0.14, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color.cyan.opacity(0.12), Color.clear],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "wallet.pass")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No cards yet")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Tap + below to add a photo of a tier card or status screen. You can edit details anytime.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            addCardFloatingButton
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func currentCardDisplayTitle(for card: RewardWalletCard?) -> String {
        guard let card else { return "Reward card" }
        let t = card.rewardProgram.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Reward card" : t
    }

    private var addCardFloatingButton: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    importedImageForNewCard = nil
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            Button {
                importedImageForNewCard = nil
                showLibrary = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 58, height: 58)
                .background(
                    Circle()
                        .fill(Color.cyan)
                        .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add card")
    }

    private let walletBottomChromeHeight: CGFloat = 118
    /// Bottom bar in expanded layout: centered add + collapse control.
    private let expandedWalletBottomBarHeight: CGFloat = 108
    /// In-deck browsing: linear `scaleEffect` on the photo (base `0.5`, scaled by `walletCardImageSizeMultiplier`).
    private var walletDeckImageLinearScale: CGFloat { 0.5 * walletCardImageSizeMultiplier }

    /// Deterministic tint used to visually separate cards in the deck (Apple Wallet-style layered color cues).
    private func deckAccentColor(for card: RewardWalletCard) -> Color {
        let hash = abs(card.id.uuidString.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.62, brightness: 0.98)
    }

    private func animateCardSelectionPulse() {
        withAnimation(.easeOut(duration: 0.16)) {
            cardSelectionPulse = 1
        }
        withAnimation(.easeInOut(duration: 0.24).delay(0.08)) {
            cardSelectionPulse = 0
        }
    }

    private func updateSelectedIndex(_ candidate: Int) {
        let clamped = min(max(0, candidate), max(0, cards.count - 1))
        guard clamped != selectedIndex else { return }
        withAnimation(.interpolatingSpring(stiffness: 220, damping: 24)) {
            selectedIndex = clamped
        }
    }

    private var walletStackWithChrome: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                let horizontalPadding: CGFloat = 14
                let stackTopInset: CGFloat = useExpandedSingleCardLayout ? 6 : 66
                let w = max(0, geo.size.width - horizontalPadding * 2)
                let bottomChromeH = useExpandedSingleCardLayout ? expandedWalletBottomBarHeight : walletBottomChromeHeight
                let h = max(
                    220 * walletCardImageSizeMultiplier,
                    geo.size.height - bottomChromeH - geo.safeAreaInsets.bottom - stackTopInset - 8
                )
                Group {
                    if useExpandedSingleCardLayout, let card = card(at: safeSelectedIndex) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 4)
                            ZStack(alignment: .top) {
                                WalletCardFaceView(
                                    card: card,
                                    image: walletStore.image(for: card),
                                    isFront: true,
                                    showsFooterOverlay: true,
                                    deckImageLinearScale: 1,
                                    showsTierHistoryOverlay: historyOverlayCardID == card.id
                                )
                                .rotation3DEffect(
                                    .degrees(cardSelectionPulse * 5),
                                    axis: (x: 0, y: 1, z: 0),
                                    perspective: 0.75
                                )
                                HStack(alignment: .top, spacing: 10) {
                                    WalletActionIconButton(
                                        systemImage: "square.and.pencil",
                                        accessibilityLabel: "Edit card",
                                        iconFont: .title2.weight(.semibold),
                                        width: 56,
                                        height: 48,
                                        cornerRadius: 14
                                    ) {
                                        cardToEdit = card
                                    }
                                    WalletActionIconButton(
                                        systemImage: historyOverlayCardID == card.id ? "clock.badge.checkmark.fill" : "chart.line.uptrend.xyaxis",
                                        accessibilityLabel: historyOverlayCardID == card.id ? "Hide tier history overlay" : "Show tier history overlay",
                                        iconFont: .title2.weight(.semibold),
                                        width: 56,
                                        height: 48,
                                        cornerRadius: 14
                                    ) {
                                        toggleTierHistoryOverlay(for: card)
                                    }
                                    Spacer(minLength: 0)
                                    WalletActionIconButton(
                                        systemImage: "info.circle.fill",
                                        accessibilityLabel: "Card details",
                                        iconFont: .title2.weight(.semibold),
                                        width: 56,
                                        height: 48,
                                        cornerRadius: 14
                                    ) {
                                        cardForDetail = card
                                    }
                                }
                                .padding(12)
                            }
                            .frame(width: w, height: h)
                            .shadow(color: .black.opacity(0.42), radius: 18, y: 8)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, stackTopInset)
                        .contentShape(Rectangle())
                        .gesture(cardDeckDragGesture)
                        .animation(.spring(response: 0.36, dampingFraction: 0.89), value: selectedIndex)
                    } else {
                        ZStack {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                                let depth = safeSelectedIndex - index
                                let cardsAboveFront = max(0, depth)
                                let cardsBelowFront = max(0, index - safeSelectedIndex)
                                let yOffset = -CGFloat(cardsAboveFront) * 34
                                    + CGFloat(cardsBelowFront) * 28
                                    + dragGestureTranslation * 0.26
                                let scale = 1 - 0.012 * CGFloat(cardsAboveFront) - 0.006 * CGFloat(cardsBelowFront)
                                let depthOpacity = max(
                                    0.56,
                                    1 - 0.045 * CGFloat(min(cardsAboveFront, 7)) - 0.055 * CGFloat(min(cardsBelowFront, 3))
                                )
                                WalletCardFaceView(
                                    card: card,
                                    image: walletStore.image(for: card),
                                    isFront: index == safeSelectedIndex,
                                    showsFooterOverlay: false,
                                    deckImageLinearScale: walletDeckImageLinearScale,
                                    showsTierHistoryOverlay: index == safeSelectedIndex && historyOverlayCardID == card.id,
                                    deckAccentColor: deckAccentColor(for: card)
                                )
                                .frame(width: w, height: h)
                                .scaleEffect(scale, anchor: .center)
                                .offset(y: yOffset)
                                .rotation3DEffect(
                                    .degrees(index == safeSelectedIndex ? cardSelectionPulse * 4.5 : 0),
                                    axis: (x: 0, y: 1, z: 0),
                                    perspective: 0.75
                                )
                                .opacity(depthOpacity)
                                .shadow(
                                    color: .black.opacity(index == safeSelectedIndex ? 0.5 : 0.23),
                                    radius: index == safeSelectedIndex ? 19 : 10,
                                    y: index == safeSelectedIndex ? 10 : 8
                                )
                                .zIndex(index == safeSelectedIndex ? 1000 : Double(index))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, stackTopInset)
                        .contentShape(Rectangle())
                        .gesture(cardDeckDragGesture)
                        .onTapGesture {
                            guard rewardsSelectionHandler == nil else { return }
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                                walletStackCollapsed = false
                            }
                        }
                        .animation(.spring(response: 0.36, dampingFraction: 0.89), value: selectedIndex)
                    }
                }
            }

            if useExpandedSingleCardLayout {
                expandedWalletBottomChrome
                    .frame(height: expandedWalletBottomBarHeight)
                    .frame(maxWidth: .infinity)
            } else {
                walletBottomChrome
                    .frame(height: walletBottomChromeHeight)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var expandedWalletBottomChrome: some View {
        ZStack {
            HStack {
                Spacer(minLength: 0)
                addCardFloatingButton
                Spacer(minLength: 0)
            }
            HStack {
                Spacer(minLength: 0)
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.89)) {
                        walletStackCollapsed = true
                    }
                } label: {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 58, height: 58)
                        .background(
                            Circle()
                                .fill(Color(.systemGray6).opacity(0.28))
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .accessibilityLabel("Show stacked cards")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var cardDeckDragGesture: some Gesture {
        DragGesture()
            .updating($dragGestureTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let t = value.translation.height
                let idx = min(max(0, selectedIndex), max(0, cards.count - 1))
                if t < -52 {
                    updateSelectedIndex(idx - 1)
                } else if t > 52 {
                    updateSelectedIndex(idx + 1)
                }
            }
    }

    private var walletBottomChrome: some View {
        let front = card(at: safeSelectedIndex)
        return Group {
            if let onPick = rewardsSelectionHandler {
                selectionWalletBottomChrome(front: front, onPick: onPick)
            } else {
                browseWalletBottomChrome(front: front)
            }
        }
    }

    private func browseWalletBottomChrome(front: RewardWalletCard?) -> some View {
        VStack(spacing: 10) {
            Text(currentCardDisplayTitle(for: front))
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.89)) {
                        walletStackCollapsed = false
                    }
                }

            ZStack {
                HStack(spacing: 12) {
                    if let c = front {
                        WalletActionIconButton(
                            systemImage: "square.and.pencil",
                            accessibilityLabel: "Edit card",
                            iconFont: .title2.weight(.semibold),
                            width: 64,
                            height: 54,
                            cornerRadius: 14
                        ) {
                            cardToEdit = c
                        }
                        WalletActionIconButton(
                            systemImage: historyOverlayCardID == c.id ? "clock.badge.checkmark.fill" : "chart.line.uptrend.xyaxis",
                            accessibilityLabel: historyOverlayCardID == c.id ? "Hide tier history overlay" : "Show tier history overlay",
                            iconFont: .title2.weight(.semibold),
                            width: 64,
                            height: 54,
                            cornerRadius: 14
                        ) {
                            toggleTierHistoryOverlay(for: c)
                        }
                    } else {
                        WalletActionIconButton(
                            systemImage: "square.and.pencil",
                            accessibilityLabel: "Edit card",
                            iconFont: .title2.weight(.semibold),
                            width: 64,
                            height: 54,
                            cornerRadius: 14
                        ) { }
                        .hidden()
                        WalletActionIconButton(
                            systemImage: "chart.line.uptrend.xyaxis",
                            accessibilityLabel: "Show tier history overlay",
                            iconFont: .title2.weight(.semibold),
                            width: 64,
                            height: 54,
                            cornerRadius: 14
                        ) { }
                        .hidden()
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        Button {
                            updateSelectedIndex(safeSelectedIndex + 1)
                        } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .disabled(safeSelectedIndex >= cards.count - 1)
                        .buttonStyle(.plain)
                        Button {
                            updateSelectedIndex(safeSelectedIndex - 1)
                        } label: {
                            Image(systemName: "chevron.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .disabled(safeSelectedIndex <= 0)
                        .buttonStyle(.plain)
                    }
                }
                WalletActionIconButton(
                    systemImage: "info.circle.fill",
                    accessibilityLabel: "Card details",
                    iconFont: .title.weight(.semibold),
                    width: 80,
                    height: 58,
                    cornerRadius: 16
                ) {
                    if let c = front { cardForDetail = c }
                }
            }
            .padding(.horizontal, 4)

            Text("Tap anywhere on the stack to enlarge · Swipe to move through cards")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func selectionWalletBottomChrome(front: RewardWalletCard?, onPick: @escaping (RewardWalletCard) -> Void) -> some View {
        VStack(spacing: 12) {
            Text(currentCardDisplayTitle(for: front))
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button {
                if let c = front { onPick(c) }
            } label: {
                Text("Use this card")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(front == nil)

            Text("Swipe the stack to choose a card, then tap Use this card.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func toggleTierHistoryOverlay(for card: RewardWalletCard) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if historyOverlayCardID == card.id {
                historyOverlayCardID = nil
            } else {
                historyOverlayCardID = card.id
            }
        }
    }

    private func shareFrontCard(includeTierHistoryOverlay: Bool) {
        guard let card = card(at: safeSelectedIndex),
              let photo = walletStore.image(for: card) else { return }
        let shareContent = TierTapWalletShareCard(
            photo: photo,
            card: card,
            gradient: settingsStore.primaryGradient,
            includeTierHistoryOverlay: includeTierHistoryOverlay
        )
        guard let image = renderShareImage(shareContent) else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss"
        let name = "TierTapWallet_\(df.string(from: Date())).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = image.pngData(), (try? data.write(to: url)) != nil else { return }
        shareURL = url
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showShareSheet = true
        }
    }

    @MainActor
    private func renderShareImage(_ view: TierTapWalletShareCard) -> UIImage? {
        let width = ShareImageExportQuality.wideCardWidthPoints
        let height: CGFloat = width * 1.25
        let wrapped = view
            .frame(width: width, height: height)
            .background(Color.black)
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = ShareImageExportQuality.imageRendererScale
            renderer.proposedSize = ProposedViewSize(width: width, height: height)
            return renderer.uiImage
        } else {
            let controller = UIHostingController(rootView: wrapped)
            controller.view.bounds = CGRect(origin: .zero, size: CGSize(width: width, height: height))
            controller.view.backgroundColor = .clear
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
            return renderer.image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
        }
    }
}

// MARK: - Card face

private struct WalletPhotoSizingModifier: ViewModifier {
    let deckBrowsing: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if deckBrowsing {
            content.scaledToFit()
        } else {
            content.scaledToFill()
        }
    }
}

private struct WalletCardFaceView: View {
    let card: RewardWalletCard
    let image: UIImage?
    let isFront: Bool
    /// When `false`, only the photo is shown (title lives in the bottom chrome while browsing the deck).
    var showsFooterOverlay: Bool = true
    /// `1` = full-bleed photo; `< 1` shrinks the photo for stacked deck browsing (e.g. `0.25` = 75% smaller linearly).
    var deckImageLinearScale: CGFloat = 1
    var showsTierHistoryOverlay: Bool = false
    var deckAccentColor: Color? = nil

    private var isDeckBrowsing: Bool { abs(deckImageLinearScale - 1) > 0.001 }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                Color.black
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .modifier(WalletPhotoSizingModifier(deckBrowsing: isDeckBrowsing))
                    } else {
                        Color(.systemGray4)
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .scaleEffect(deckImageLinearScale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay {
                if isDeckBrowsing, let deckAccentColor {
                    LinearGradient(
                        colors: [
                            deckAccentColor.opacity(isFront ? 0.28 : 0.34),
                            deckAccentColor.opacity(0.12),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                    .allowsHitTesting(false)
                }
            }

            if showsTierHistoryOverlay {
                TierHistoryOverlayPanel(entries: card.tierHistory)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
            }

            if showsFooterOverlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .frame(maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.rewardProgram.isEmpty ? "Reward program" : card.rewardProgram)
                        .font(isFront ? .title3.bold() : .caption.bold())
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if !card.currentTier.isEmpty {
                        Text(card.currentTier)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.cyan.opacity(0.95))
                    }
                    if let exp = card.expirationDate {
                        Text("Exp. \(exp.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    isDeckBrowsing
                    ? (deckAccentColor ?? .white).opacity(isFront ? 0.48 : 0.28)
                    : Color.white.opacity(0.18),
                    lineWidth: isDeckBrowsing ? 1.15 : 1
                )
        )
    }
}

private struct TierHistoryOverlayPanel: View {
    let entries: [RewardWalletCard.TierHistoryEntry]

    fileprivate struct DataPoint: Identifiable {
        let id: UUID
        let x: Double
        let y: Double
        let tier: String
        let date: Date
    }

    private var dataPoints: [DataPoint] {
        let sorted = entries.sorted { $0.recordedAt < $1.recordedAt }
        guard !sorted.isEmpty else { return [] }

        let asIntegers = sorted.compactMap { Int($0.tier.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let shouldUseNumeric = asIntegers.count == sorted.count

        if shouldUseNumeric {
            return sorted.enumerated().map { idx, entry in
                DataPoint(
                    id: entry.id,
                    x: Double(idx),
                    y: Double(Int(entry.tier.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0),
                    tier: entry.tier,
                    date: entry.recordedAt
                )
            }
        }

        var tierOrdering: [String: Double] = [:]
        var nextY: Double = 1
        return sorted.enumerated().map { idx, entry in
            let key = entry.tier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if tierOrdering[key] == nil {
                tierOrdering[key] = nextY
                nextY += 1
            }
            return DataPoint(
                id: entry.id,
                x: Double(idx),
                y: tierOrdering[key] ?? 1,
                tier: entry.tier,
                date: entry.recordedAt
            )
        }
    }

    private var latestLabel: String {
        entries.sorted { $0.recordedAt < $1.recordedAt }.last?.tier ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.cyan.opacity(0.9))
                Text("Tier history")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))
                Spacer(minLength: 0)
                Text(latestLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.84))
                    .lineLimit(1)
            }

            if dataPoints.count >= 2 {
                TierHistorySparkline(dataPoints: dataPoints)
                    .frame(height: 72)
                HStack {
                    if let first = dataPoints.first {
                        Text(first.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.56))
                    }
                    Spacer(minLength: 0)
                    if let last = dataPoints.last {
                        Text(last.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.56))
                    }
                }
            } else if let point = dataPoints.first {
                Text("Only one saved tier point (\(point.tier)).")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.72))
            } else {
                Text("No tier history yet.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.72))
            }
        }
        .padding(10)
        .frame(maxWidth: 250, alignment: .leading)
        .background(.black.opacity(0.62))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TierHistorySparkline: View {
    let dataPoints: [TierHistoryOverlayPanel.DataPoint]

    var body: some View {
        GeometryReader { geo in
            let points = chartPoints(in: geo.size)
            ZStack {
                grid(size: geo.size)
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(index == points.count - 1 ? Color.cyan : Color.white.opacity(0.8))
                        .frame(width: index == points.count - 1 ? 7 : 5, height: index == points.count - 1 ? 7 : 5)
                        .position(point)
                }
            }
        }
    }

    private func grid(size: CGSize) -> some View {
        Path { path in
            let rows: CGFloat = 3
            for row in 0...Int(rows) {
                let y = size.height * CGFloat(row) / rows
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !dataPoints.isEmpty else { return [] }
        let minY = dataPoints.map(\.y).min() ?? 0
        let maxY = dataPoints.map(\.y).max() ?? 0
        let ySpan = max(1, maxY - minY)
        let xMax = max(1, Double(dataPoints.count - 1))
        return dataPoints.map { point in
            let xNorm = point.x / xMax
            let yNorm = (point.y - minY) / ySpan
            return CGPoint(
                x: CGFloat(xNorm) * size.width,
                y: (1 - CGFloat(yNorm)) * size.height
            )
        }
    }
}

private struct WalletShareOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var includeTierHistoryOverlay: Bool
    let onShare: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Share options") {
                    Toggle("Include tier history overlay", isOn: $includeTierHistoryOverlay)
                }
            }
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        onShare()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

/// Icon-only control styled like Check In secondary pills (`systemGray6` fill, white symbol).
private struct WalletActionIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var iconFont: Font = .title3.weight(.semibold)
    var width: CGFloat = 52
    var height: CGFloat = 46
    var cornerRadius: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(iconFont)
                .foregroundColor(.white)
                .frame(width: width, height: height)
                .background(Color(.systemGray6).opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Read-only detail

private struct WalletCardDetailSheet: View {
    @EnvironmentObject private var walletStore: RewardWalletStore
    @Environment(\.dismiss) private var dismiss

    let card: RewardWalletCard

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let img = walletStore.image(for: card) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: WalletHeroImageLayout.maxHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    detailRow(title: "Reward program", value: card.rewardProgram.isEmpty ? "—" : card.rewardProgram)
                    detailRow(title: "Current tier", value: card.currentTier.isEmpty ? "—" : card.currentTier)
                    detailRow(
                        title: "Expiration",
                        value: card.expirationDate.map { $0.formatted(date: .long, time: .omitted) } ?? "—"
                    )
                    detailRow(title: "Notes", value: card.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : card.notes)
                }
                .padding()
            }
            .navigationTitle("Card details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.green)
                }
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Share render target

private struct TierTapWalletShareCard: View {
    let photo: UIImage
    let card: RewardWalletCard
    let gradient: LinearGradient
    var includeTierHistoryOverlay: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 280)
                    .clipped()
                if includeTierHistoryOverlay {
                    TierHistoryOverlayPanel(entries: card.tierHistory)
                        .padding(12)
                }
            }

            ZStack(alignment: .bottomLeading) {
                gradient
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reward program")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.65))
                    Text(card.rewardProgram.isEmpty ? "—" : card.rewardProgram)
                        .font(.headline)
                        .foregroundColor(.white)
                    labeledRow(title: "Current tier", value: card.currentTier.isEmpty ? "—" : card.currentTier)
                    labeledRow(
                        title: "Expiration",
                        value: card.expirationDate.map { $0.formatted(date: .long, time: .omitted) } ?? "—"
                    )
                    if !card.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        labeledRow(title: "Notes", value: card.notes)
                    }
                    Text("TierTap")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.top, 4)
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func labeledRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - New card

private struct NewWalletCardSheet: View {
    @EnvironmentObject private var walletStore: RewardWalletStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    let initialImage: UIImage
    var onSaved: () -> Void

    @State private var rewardProgram = ""
    @State private var currentTier = ""
    @State private var hasExpiration = false
    @State private var expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: initialImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: WalletHeroImageLayout.maxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Section("Details") {
                    RewardProgramFieldWithSharedPresets(casino: "", programText: $rewardProgram)
                    NumericEntryWithDialPad(
                        placeholder: "Current tier",
                        text: $currentTier,
                        dialPadNavigationTitle: "Current tier"
                    )
                    Toggle("Expiration date", isOn: $hasExpiration)
                    if hasExpiration {
                        DatePicker("Expires", selection: $expirationDate, displayedComponents: .date)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("New card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedProgram = rewardProgram.trimmingCharacters(in: .whitespacesAndNewlines)
                        let ok = walletStore.addCard(
                            image: initialImage,
                            rewardProgram: rewardProgram,
                            currentTier: currentTier,
                            expirationDate: hasExpiration ? expirationDate : nil,
                            notes: notes
                        )
                        if ok {
                            if !trimmedProgram.isEmpty {
                                settingsStore.rememberRewardProgramName(trimmedProgram)
                            }
                            CelebrationPlayer.shared.playQuickChime()
                            onSaved()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                }
            }
        }
    }
}

// MARK: - Edit card

private struct EditWalletCardSheet: View {
    @EnvironmentObject private var walletStore: RewardWalletStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    let card: RewardWalletCard
    var onFinished: () -> Void

    @State private var rewardProgram: String = ""
    @State private var currentTier: String = ""
    @State private var hasExpiration: Bool = false
    @State private var expirationDate: Date = Date()
    @State private var notes: String = ""
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var retakeImage: UIImage?
    @State private var showResetHistoryConfirmation = false
    @State private var showDeleteCardConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let img = retakeImage ?? walletStore.image(for: card) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: WalletHeroImageLayout.maxHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Retake") { showCamera = true }
                        }
                        Button("Choose photo") { showLibrary = true }
                    }
                    .font(.subheadline)
                }
                Section("Details") {
                    RewardProgramFieldWithSharedPresets(casino: "", programText: $rewardProgram)
                    NumericEntryWithDialPad(
                        placeholder: "Current tier",
                        text: $currentTier,
                        dialPadNavigationTitle: "Current tier"
                    )
                    Toggle("Expiration date", isOn: $hasExpiration)
                    if hasExpiration {
                        DatePicker("Expires", selection: $expirationDate, displayedComponents: .date)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Button("Reset tier history", role: .destructive) {
                        showResetHistoryConfirmation = true
                    }
                    Text("Keeps the current tier as a new baseline after reset.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Section {
                    Button("Delete card", role: .destructive) {
                        showDeleteCardConfirmation = true
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit card")
                        .font(.headline)
                        .foregroundColor(.green)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onFinished()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = card
                        updated.rewardProgram = rewardProgram
                        updated.currentTier = currentTier
                        updated.expirationDate = hasExpiration ? expirationDate : nil
                        updated.notes = notes
                        walletStore.updateCard(updated, newImage: retakeImage)
                        let trimmedProgram = rewardProgram.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedProgram.isEmpty {
                            settingsStore.rememberRewardProgramName(trimmedProgram)
                        }
                        onFinished()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                }
            }
            .onAppear {
                rewardProgram = card.rewardProgram
                currentTier = card.currentTier
                notes = card.notes
                if let exp = card.expirationDate {
                    hasExpiration = true
                    expirationDate = exp
                } else {
                    hasExpiration = false
                }
            }
            .sheet(isPresented: $showCamera) {
                ProfilePhotoCaptureView(image: $retakeImage, preferredSourceType: .camera)
            }
            .sheet(isPresented: $showLibrary) {
                ImagePicker(selectedImage: $retakeImage, onImagePicked: { _ in })
            }
            .alert("Reset tier history?", isPresented: $showResetHistoryConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset history", role: .destructive) {
                    walletStore.resetTierHistory(for: card.id, preserveCurrentTierSnapshot: true)
                }
            } message: {
                Text("This clears previous tier progression for this card. You cannot undo it.")
            }
            .alert("Delete this wallet card?", isPresented: $showDeleteCardConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete card", role: .destructive) {
                    walletStore.deleteCard(id: card.id)
                    onFinished()
                    dismiss()
                }
            } message: {
                Text("This permanently removes the card photo, details, and tier history.")
            }
        }
    }
}
#endif
