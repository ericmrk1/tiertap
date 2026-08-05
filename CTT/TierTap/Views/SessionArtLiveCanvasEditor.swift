import SwiftUI
import UIKit

#if os(iOS)

/// Live canvas editor: pan/zoom underlay, drag/scale/rotate metrics & text layers,
/// layer lock/hide, my-styles, shuffle, and export tools (WP-E1–E8 / X1 / X5).
struct SessionArtLiveCanvasEditor: View {
    let session: Session
    @Binding var layout: SessionArtLayout
    @Binding var privacy: SessionArtPrivacyPreset
    @Binding var aspect: SessionArtAspectRatio
    @Binding var selectedBaseTemplate: SessionArtTemplate
    @Binding var selectedStickerTemplate: SessionArtTemplate?
    @Binding var selectedArtDecoTemplate: SessionArtTemplate?
    @Binding var selectedTextFont: SessionArtTextFont
    @Binding var globalTextScale: CGFloat
    @Binding var selectedTextColor: SessionArtColorToken
    @Binding var selectedTextBackgroundColor: SessionArtColorToken
    @Binding var textBackgroundOpacity: CGFloat
    @Binding var footerCaption: String
    @Binding var customHeadline: String
    let underlay: UIImage?
    let currencySymbol: String
    var onShare: (UIImage) -> Void
    var onShareItems: ([Any]) -> Void
    var onShareTransparent: (UIImage) -> Void
    var onShareAnimated: (URL) -> Void
    var onShareInstagram: (UIImage) -> Void
    var onSavePhotos: (UIImage) -> Void
    var onCancel: () -> Void

    private enum CanvasLayer: Hashable {
        case metric(MetricLineKey)
        case headline
        case caption
    }

    private enum ToolRail: String, CaseIterable, Identifiable {
        case arrange
        case layers
        case type
        case styles
        case export
        var id: String { rawValue }
        var title: String {
            switch self {
            case .arrange: return "Arrange"
            case .layers: return "Layers"
            case .type: return "Type"
            case .styles: return "Styles"
            case .export: return "Export"
            }
        }
    }

    @State private var previewImage: UIImage?
    @State private var isRendering = false
    @State private var selectedLayer: CanvasLayer?
    @State private var canvasFrame: CGRect = .zero
    @State private var underlayDragStart: CGPoint?
    @State private var layerDragStart: CGPoint?
    @State private var pinchStartZoom: CGFloat = 1
    @State private var metricPinchStartScale: CGFloat = 1
    @State private var metricRotateStart: CGFloat = 0
    @State private var toolRail: ToolRail = .arrange
    @State private var isExportingAnimated = false
    @State private var exportMessage: String?
    @State private var layoutSourceCanvas: CGSize = SessionArtAspectRatio.story.canvasSize
    @State private var savedStyles: [SessionArtNamedComposition] = SessionArtCompositionStore.loadAll()
    @State private var styleNameDraft = ""
    @State private var showSaveStyleAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    canvasArea
                    toolControls
                }
                if isExportingAnimated {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    ProgressView("Rendering animated story…")
                        .tint(.white)
                        .foregroundColor(.white)
                        .padding(18)
                        .background(Color.black.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .navigationTitle("Session Art Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onCancel)
                        .foregroundColor(.green)
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        if let previewImage { onSavePhotos(previewImage) }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .foregroundColor(.green)
                    .disabled(previewImage == nil)
                    .accessibilityLabel("Save to Photos")

                    Button {
                        if let previewImage { onShare(previewImage) }
                    } label: {
                        Text("Share")
                    }
                    .foregroundColor(.green)
                    .disabled(previewImage == nil)
                }
            }
            .alert("Save style", isPresented: $showSaveStyleAlert) {
                TextField("Name", text: $styleNameDraft)
                Button("Save") { saveCurrentStyle() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved under My styles for reuse.")
            }
            .onAppear {
                layoutSourceCanvas = aspect.canvasSize
                savedStyles = SessionArtCompositionStore.loadAll()
                refreshPreview()
            }
            .onChange(of: layout) { _ in refreshPreview() }
            .onChange(of: privacy) { _ in refreshPreview() }
            .onChange(of: aspect) { _ in
                let newSize = aspect.canvasSize
                layout = layout.scaledForCanvas(from: layoutSourceCanvas, to: newSize)
                layoutSourceCanvas = newSize
                SessionArtSharePresetStore.lastAspectRatio = aspect
                refreshPreview()
            }
            .onChange(of: selectedTextFont) { _ in refreshPreview() }
            .onChange(of: globalTextScale) { _ in refreshPreview() }
            .onChange(of: selectedTextColor) { _ in refreshPreview() }
            .onChange(of: selectedTextBackgroundColor) { _ in refreshPreview() }
            .onChange(of: textBackgroundOpacity) { _ in refreshPreview() }
            .onChange(of: footerCaption) { _ in refreshPreview() }
            .onChange(of: customHeadline) { _ in refreshPreview() }
        }
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            let viewAspect = aspect.aspect
            let maxW = geo.size.width - 24
            let maxH = geo.size.height - 12
            let heightFromWidth = maxW / viewAspect
            let widthFromHeight = maxH * viewAspect
            let displaySize: CGSize = heightFromWidth <= maxH
                ? CGSize(width: maxW, height: heightFromWidth)
                : CGSize(width: widthFromHeight, height: maxH)

            ZStack {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .clipped()
                } else {
                    ProgressView()
                        .tint(.white)
                        .frame(width: displaySize.width, height: displaySize.height)
                }

                ForEach(visibleMetricKeys, id: \.self) { key in
                    metricHandle(for: key, displaySize: displaySize)
                }
                if !layout.headerHidden {
                    textLayerHandle(.headline, at: layout.headerOrigin, label: "H", displaySize: displaySize)
                }
                if !layout.footerHidden {
                    textLayerHandle(.caption, at: layout.footerCenter, label: "C", displaySize: displaySize)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .contentShape(Rectangle())
            .gesture(underlayGesture(displaySize: displaySize))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .onAppear { canvasFrame = CGRect(origin: .zero, size: displaySize) }
            .onChange(of: displaySize.width) { _ in canvasFrame = CGRect(origin: .zero, size: displaySize) }
        }
        .frame(maxHeight: .infinity)
    }

    private var allMetricKeys: [MetricLineKey] {
        SessionArtLayout.activeLineKeys(
            session: session,
            publishTierPerHour: privacy.publishTierPerHour,
            publishWinLoss: privacy.publishWinLoss,
            publishBuyInCashOut: privacy.publishBuyInCashOut,
            publishCompDetails: privacy.publishCompDetails
        )
    }

    private var visibleMetricKeys: [MetricLineKey] {
        allMetricKeys.filter { !layout.isLineHidden($0) }
    }

    private func metricHandle(for key: MetricLineKey, displaySize: CGSize) -> some View {
        let canvas = aspect.canvasSize
        let origin = layout.lineOrigins[key] ?? CGPoint(x: canvas.width * 0.1, y: canvas.height * 0.5)
        let x = origin.x / canvas.width * displaySize.width
        let y = origin.y / canvas.height * displaySize.height
        let selected = selectedLayer == .metric(key)
        let locked = layout.isLineLocked(key)
        return Circle()
            .strokeBorder(selected ? Color.green : Color.white.opacity(0.55), lineWidth: selected ? 3 : 1.5)
            .background(Circle().fill(Color.black.opacity(selected ? 0.35 : 0.15)))
            .overlay {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: selected ? 44 : 34, height: selected ? 44 : 34)
            .position(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectedLayer = .metric(key)
                        guard !layout.isLineLocked(key) else { return }
                        if layerDragStart == nil {
                            layerDragStart = layout.lineOrigins[key]
                        }
                        guard let start = layerDragStart else { return }
                        let dx = value.translation.width / displaySize.width * canvas.width
                        let dy = value.translation.height / displaySize.height * canvas.height
                        layout.lineOrigins[key] = CGPoint(x: start.x + dx, y: start.y + dy)
                    }
                    .onEnded { _ in
                        layerDragStart = nil
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        selectedLayer = .metric(key)
                        guard !layout.isLineLocked(key) else { return }
                        if metricPinchStartScale == 1 || abs((layout.lineScales[key] ?? 1) - metricPinchStartScale) > 0.2 {
                            metricPinchStartScale = layout.lineScales[key] ?? 1
                        }
                        layout.lineScales[key] = min(2.5, max(0.45, metricPinchStartScale * scale))
                    }
                    .onEnded { _ in
                        metricPinchStartScale = layout.lineScales[key] ?? 1
                    }
            )
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { angle in
                        selectedLayer = .metric(key)
                        guard !layout.isLineLocked(key) else { return }
                        if selectedLayer != .metric(key) {
                            metricRotateStart = layout.lineRotations[key] ?? 0
                        }
                        layout.lineRotations[key] = metricRotateStart + CGFloat(angle.radians)
                    }
                    .onEnded { _ in
                        metricRotateStart = layout.lineRotations[key] ?? 0
                    }
            )
            .onTapGesture { selectedLayer = .metric(key) }
    }

    private func textLayerHandle(_ layer: CanvasLayer, at origin: CGPoint, label: String, displaySize: CGSize) -> some View {
        let canvas = aspect.canvasSize
        let x = origin.x / canvas.width * displaySize.width
        let y = origin.y / canvas.height * displaySize.height
        let selected = selectedLayer == layer
        let locked = layer == .headline ? layout.headerLocked : layout.footerLocked
        return RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selected ? Color.green : Color.cyan.opacity(0.8), lineWidth: selected ? 3 : 1.5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(selected ? 0.4 : 0.2)))
            .overlay {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(width: selected ? 48 : 40, height: selected ? 36 : 30)
            .position(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectedLayer = layer
                        let isLocked = layer == .headline ? layout.headerLocked : layout.footerLocked
                        guard !isLocked else { return }
                        if layerDragStart == nil {
                            layerDragStart = layer == .headline ? layout.headerOrigin : layout.footerCenter
                        }
                        guard let start = layerDragStart else { return }
                        let dx = value.translation.width / displaySize.width * canvas.width
                        let dy = value.translation.height / displaySize.height * canvas.height
                        let next = CGPoint(x: start.x + dx, y: start.y + dy)
                        if layer == .headline {
                            layout.headerOrigin = next
                        } else {
                            layout.footerCenter = next
                        }
                    }
                    .onEnded { _ in layerDragStart = nil }
            )
            .onTapGesture { selectedLayer = layer }
    }

    private func underlayGesture(displaySize: CGSize) -> some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard selectedLayer == nil else { return }
                    if underlayDragStart == nil {
                        underlayDragStart = layout.underlayPan
                    }
                    let start = underlayDragStart ?? .zero
                    let canvas = aspect.canvasSize
                    let dx = value.translation.width / displaySize.width * canvas.width
                    let dy = value.translation.height / displaySize.height * canvas.height
                    layout.underlayPan = CGPoint(x: start.x + dx, y: start.y + dy)
                }
                .onEnded { _ in underlayDragStart = nil },
            MagnificationGesture()
                .onChanged { scale in
                    guard selectedLayer == nil else { return }
                    if abs(pinchStartZoom - layout.underlayZoom) > 0.001 && underlayDragStart == nil && pinchStartZoom == 1 {
                        pinchStartZoom = layout.underlayZoom
                    }
                    let base = pinchStartZoom == 1 ? layout.underlayZoom : pinchStartZoom
                    layout.underlayZoom = min(3.5, max(1.0, base * scale))
                }
                .onEnded { _ in
                    pinchStartZoom = layout.underlayZoom
                }
        )
    }

    private var toolControls: some View {
        VStack(spacing: 10) {
            Picker("", selection: $toolRail) {
                ForEach(ToolRail.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Group {
                switch toolRail {
                case .arrange:
                    arrangeTools
                case .layers:
                    layersTools
                case .type:
                    typeTools
                case .styles:
                    stylesTools
                case .export:
                    exportTools
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .background(Color.white.opacity(0.08))
    }

    private var arrangeTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.7))
            Picker("", selection: $privacy) {
                ForEach(SessionArtPrivacyPreset.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Text("Format")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.7))
            Picker("", selection: $aspect) {
                ForEach(SessionArtAspectRatio.allCases) { a in
                    Text(a.title).tag(a)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button("Shuffle") { shuffleStyle() }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(10)

                Button("Deselect") { selectedLayer = nil }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)

                Spacer()
                Text(selectionHint)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }

    private var selectionHint: String {
        switch selectedLayer {
        case .metric(let key): return key.displayName
        case .headline: return "Headline"
        case .caption: return "Caption"
        case .none: return "Drag photo · H/C text · metric dots"
        }
    }

    private var layersTools: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layers")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.7))

            layerRow(
                title: "Headline",
                selected: selectedLayer == .headline,
                hidden: layout.headerHidden,
                locked: layout.headerLocked,
                onSelect: { selectedLayer = .headline },
                onToggleHidden: { layout.headerHidden.toggle() },
                onToggleLocked: { layout.headerLocked.toggle() }
            )
            layerRow(
                title: "Caption",
                selected: selectedLayer == .caption,
                hidden: layout.footerHidden,
                locked: layout.footerLocked,
                onSelect: { selectedLayer = .caption },
                onToggleHidden: { layout.footerHidden.toggle() },
                onToggleLocked: { layout.footerLocked.toggle() }
            )

            ForEach(allMetricKeys, id: \.self) { key in
                layerRow(
                    title: key.displayName,
                    selected: selectedLayer == .metric(key),
                    hidden: layout.isLineHidden(key),
                    locked: layout.isLineLocked(key),
                    onSelect: { selectedLayer = .metric(key) },
                    onToggleHidden: {
                        layout.setLineHidden(key, !layout.isLineHidden(key))
                    },
                    onToggleLocked: {
                        layout.setLineLocked(key, !layout.isLineLocked(key))
                    }
                )
            }
        }
    }

    private func layerRow(
        title: String,
        selected: Bool,
        hidden: Bool,
        locked: Bool,
        onSelect: @escaping () -> Void,
        onToggleHidden: @escaping () -> Void,
        onToggleLocked: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                Text(title)
                    .font(.caption.weight(selected ? .bold : .medium))
                    .foregroundColor(selected ? .green : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onToggleHidden) {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .foregroundColor(hidden ? .orange : .white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Button(action: onToggleLocked) {
                Image(systemName: locked ? "lock.fill" : "lock.open")
                    .foregroundColor(locked ? .yellow : .white.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(selected ? Color.white.opacity(0.12) : Color.clear)
        .cornerRadius(8)
    }

    private var typeTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Font", selection: $selectedTextFont) {
                ForEach(SessionArtTextFont.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)

            HStack {
                Text("Size")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.caption)
                Slider(value: $globalTextScale, in: 0.8...1.8)
                    .tint(.green)
            }
            HStack {
                Text("BG")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.caption)
                Slider(value: $textBackgroundOpacity, in: 0...0.9)
                    .tint(.green)
            }
            TextField("Custom headline", text: $customHeadline)
                .textFieldStyle(.roundedBorder)
            TextField("Caption / footnote", text: $footerCaption)
                .textFieldStyle(.roundedBorder)
            Text("Drag the H / C handles on the canvas to place text.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var stylesTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    styleNameDraft = "My style \(savedStyles.count + 1)"
                    showSaveStyleAlert = true
                } label: {
                    Label("Save current", systemImage: "square.and.arrow.down.on.square")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button("Shuffle") { shuffleStyle() }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .buttonStyle(.plain)
            }

            if savedStyles.isEmpty {
                Text("No saved styles yet.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
            } else {
                Text("My styles")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.7))
                ForEach(savedStyles) { style in
                    HStack {
                        Button {
                            applyStyle(style)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                Text(style.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            SessionArtCompositionStore.delete(id: style.id)
                            savedStyles = SessionArtCompositionStore.loadAll()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var exportTools: some View {
        VStack(spacing: 10) {
            if let exportMessage {
                Text(exportMessage)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }

            HStack(spacing: 10) {
                Button {
                    if let previewImage { onShare(previewImage) }
                } label: {
                    exportButtonLabel("Share", systemImage: "square.and.arrow.up", color: .red)
                }
                .buttonStyle(.plain)

                Button {
                    if let previewImage { onSavePhotos(previewImage) }
                } label: {
                    exportButtonLabel("Save", systemImage: "square.and.arrow.down", color: .blue)
                }
                .buttonStyle(.plain)
            }

            Button {
                shareStoryAndFeed()
            } label: {
                exportButtonLabel("Share Story + Feed", systemImage: "rectangle.stack", color: .indigo)
            }
            .buttonStyle(.plain)

            if InstagramStoriesSharer.isAvailable {
                Button {
                    if let previewImage { onShareInstagram(previewImage) }
                } label: {
                    exportButtonLabel("Instagram Stories", systemImage: "camera.filters", color: .purple)
                }
                .buttonStyle(.plain)
            }

            Button {
                let image = SessionArtQuickShareRenderer.renderTransparentOverlay(
                    session: session,
                    currencySymbol: currencySymbol,
                    privacy: privacy,
                    layout: layout,
                    aspect: aspect,
                    font: selectedTextFont,
                    textScale: globalTextScale,
                    textColor: selectedTextColor,
                    bgColor: selectedTextBackgroundColor,
                    bgOpacity: textBackgroundOpacity,
                    footerCaption: footerCaption,
                    customHeadline: customHeadline
                )
                onShareTransparent(image)
            } label: {
                exportButtonLabel("Transparent overlay PNG", systemImage: "rectangle.dashed", color: .orange)
            }
            .buttonStyle(.plain)

            Button {
                exportAnimated()
            } label: {
                exportButtonLabel("Animated story video", systemImage: "film", color: Color(UIColor.systemMint))
            }
            .buttonStyle(.plain)
            .disabled(isExportingAnimated)
        }
    }

    private func exportButtonLabel(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(color.opacity(0.85))
            .foregroundStyle(.white)
            .cornerRadius(12)
    }

    private func refreshPreview() {
        isRendering = true
        let params = SessionArtRenderer.RenderParams(
            base: underlay,
            session: session,
            currencySymbol: currencySymbol,
            includeMetrics: privacy.includeMetrics,
            publishTierPerHour: privacy.publishTierPerHour,
            publishWinLoss: privacy.publishWinLoss,
            publishBuyInCashOut: privacy.publishBuyInCashOut,
            publishCompDetails: privacy.publishCompDetails,
            metricsReach: 1,
            counterGlobalT: nil,
            fontStyle: selectedTextFont,
            textScale: globalTextScale,
            textColorToken: selectedTextColor,
            textBackgroundColorToken: selectedTextBackgroundColor,
            textBackgroundOpacity: textBackgroundOpacity,
            canvasSize: aspect.canvasSize,
            layout: layout,
            footerCaption: footerCaption,
            customHeadline: customHeadline
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let image = SessionArtRenderer.renderImage(params: params)
            DispatchQueue.main.async {
                previewImage = image
                isRendering = false
            }
        }
    }

    private func exportAnimated() {
        isExportingAnimated = true
        exportMessage = nil
        SessionArtAnimatedStoryExporter.export(
            session: session,
            currencySymbol: currencySymbol,
            privacy: privacy,
            layout: layout,
            underlay: underlay,
            aspect: aspect,
            font: selectedTextFont,
            textScale: globalTextScale,
            textColor: selectedTextColor,
            bgColor: selectedTextBackgroundColor,
            bgOpacity: textBackgroundOpacity,
            footerCaption: footerCaption,
            customHeadline: customHeadline
        ) { result in
            DispatchQueue.main.async {
                isExportingAnimated = false
                switch result {
                case .success(let url):
                    onShareAnimated(url)
                case .failure(let error):
                    exportMessage = error.localizedDescription
                }
            }
        }
    }

    private func shareStoryAndFeed() {
        let images = SessionArtMultiFormatExporter.renderStoryAndFeed(
            session: session,
            currencySymbol: currencySymbol,
            privacy: privacy,
            layout: layout,
            underlay: underlay,
            sourceAspect: aspect,
            font: selectedTextFont,
            textScale: globalTextScale,
            textColor: selectedTextColor,
            bgColor: selectedTextBackgroundColor,
            bgOpacity: textBackgroundOpacity,
            footerCaption: footerCaption,
            customHeadline: customHeadline
        )
        onShareItems(images)
        exportMessage = "Story + Feed ready to share."
    }

    private func shuffleStyle() {
        let pick = SessionArtStyleRandomizer.pick()
        selectedBaseTemplate = pick.baseTemplate
        selectedStickerTemplate = pick.stickerTemplate
        selectedArtDecoTemplate = pick.artDecoTemplate
        selectedTextFont = pick.font
        selectedTextColor = pick.textColor
        selectedTextBackgroundColor = pick.bgColor
        globalTextScale = pick.textScale
        textBackgroundOpacity = pick.bgOpacity
        layout = SessionArtLayoutComposer.compose(
            session: session,
            base: pick.baseTemplate,
            sticker: pick.stickerTemplate,
            artDeco: pick.artDecoTemplate,
            privacy: privacy,
            canvasSize: aspect.canvasSize,
            preserving: layout
        )
        layoutSourceCanvas = aspect.canvasSize
        exportMessage = "Shuffled · \(pick.baseTemplate.shortTitle)"
    }

    private func saveCurrentStyle() {
        let trimmed = styleNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let composition = SessionArtNamedComposition.capture(
            name: trimmed,
            layout: layout,
            aspect: aspect,
            privacy: privacy,
            base: selectedBaseTemplate,
            sticker: selectedStickerTemplate,
            artDeco: selectedArtDecoTemplate,
            font: selectedTextFont,
            textScale: globalTextScale,
            textColor: selectedTextColor,
            bgColor: selectedTextBackgroundColor,
            bgOpacity: textBackgroundOpacity,
            footerCaption: footerCaption,
            customHeadline: customHeadline
        )
        SessionArtCompositionStore.save(composition)
        savedStyles = SessionArtCompositionStore.loadAll()
        exportMessage = "Saved “\(trimmed)”."
    }

    private func applyStyle(_ style: SessionArtNamedComposition) {
        if let a = SessionArtAspectRatio(rawValue: style.aspectRaw) {
            aspect = a
            SessionArtSharePresetStore.lastAspectRatio = a
        }
        if let p = SessionArtPrivacyPreset(rawValue: style.privacyRaw) {
            privacy = p
            SessionArtSharePresetStore.lastPrivacyPreset = p
        }
        if let base = SessionArtTemplate(rawValue: style.baseTemplateRaw) {
            selectedBaseTemplate = base
        }
        selectedStickerTemplate = style.stickerTemplateRaw.flatMap(SessionArtTemplate.init(rawValue:))
        selectedArtDecoTemplate = style.artDecoTemplateRaw.flatMap(SessionArtTemplate.init(rawValue:))
        if let font = SessionArtTextFont(rawValue: style.fontRaw) {
            selectedTextFont = font
        }
        globalTextScale = min(1.8, max(0.8, CGFloat(style.textScale)))
        if let c = SessionArtColorToken(rawValue: style.textColorRaw) {
            selectedTextColor = c
        }
        if let c = SessionArtColorToken(rawValue: style.bgColorRaw) {
            selectedTextBackgroundColor = c
        }
        textBackgroundOpacity = min(0.9, max(0, CGFloat(style.bgOpacity)))
        footerCaption = style.footerCaption
        customHeadline = style.customHeadline
        layout = style.makeLayout()
        layoutSourceCanvas = aspect.canvasSize
        exportMessage = "Loaded “\(style.name)”."
    }
}

#endif
