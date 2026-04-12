import SwiftUI
import UIKit

struct UserGuideView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    /// When `true`, show a Done button (e.g. modal presentation). When `false`, rely on back navigation.
    var showsDismissButton: Bool = false

    @State private var pdfShareURL: URL?
    @State private var isPresentingPDFShare = false
    @State private var pdfErrorMessage: String?
    @State private var showPDFError = false
    @State private var expandedTopSectionIDs: Set<String> = []
    @State private var expandedSubsectionIDs: Set<String> = []

    private var guideSections: [UserGuideTopSection] {
        UserGuideContent.guideSections(for: appLanguage)
    }

    var body: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(guideSections) { section in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedTopSectionIDs.contains(section.id) },
                                set: { expanded in
                                    if expanded {
                                        expandedTopSectionIDs.insert(section.id)
                                    } else {
                                        expandedTopSectionIDs.remove(section.id)
                                    }
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(section.subsections) { subsection in
                                    if let heading = subsection.heading {
                                        DisclosureGroup(
                                            isExpanded: Binding(
                                                get: { expandedSubsectionIDs.contains(subsection.id) },
                                                set: { expanded in
                                                    if expanded {
                                                        expandedSubsectionIDs.insert(subsection.id)
                                                    } else {
                                                        expandedSubsectionIDs.remove(subsection.id)
                                                    }
                                                }
                                            )
                                        ) {
                                            subsectionBody(rows: subsection.rows)
                                        } label: {
                                            Text(heading)
                                                .font(.headline)
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .tint(.green)
                                        .padding(12)
                                        .background(Color.black.opacity(0.22))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    } else {
                                        subsectionBody(rows: subsection.rows)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Text(section.title)
                                .font(.title3.bold())
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tint(.green)
                        .padding(14)
                        .background(Color.black.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .padding(.bottom, 24)
            }
        }
        .localizedNavigationTitle("User Guide")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        L10nText("Done")
                    }
                    .foregroundColor(.green)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportPDF()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(L10n.tr("Share user guide as PDF", language: appLanguage))
                .foregroundColor(.white)
            }
        }
        .sheet(isPresented: $isPresentingPDFShare, onDismiss: {
            if let url = pdfShareURL {
                try? FileManager.default.removeItem(at: url)
                pdfShareURL = nil
            }
        }) {
            if let url = pdfShareURL {
                ShareSheet(items: [url])
            }
        }
        .alert(L10n.tr("Couldn’t create PDF", language: appLanguage), isPresented: $showPDFError) {
            Button(role: .cancel, action: {}) {
                Text(L10n.tr("OK", language: appLanguage))
            }
        } message: {
            if let pdfErrorMessage {
                Text(pdfErrorMessage)
            } else {
                L10nText("Unknown error.")
            }
        }
    }

    @ViewBuilder
    private func subsectionBody(rows: [UserGuideRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                guideRowView(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func guideRowView(_ row: UserGuideRow) -> some View {
        switch row {
        case .h1, .h2:
            EmptyView()
        case .paragraph(let text):
            Text(text)
                .font(.body)
                .foregroundColor(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 10) {
                Text("•")
                    .font(.body.bold())
                    .foregroundColor(.green)
                Text(text)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func exportPDF() {
        let lang = appLanguage
        let body = UserGuideContent.plainTextForPDF(language: lang)
        let title = L10n.tr("TierTap User Guide", language: lang)
        guard let data = UserGuidePDFExporter.makePDF(text: body, title: title) else {
            pdfErrorMessage = L10n.tr("PDF generation failed.", language: lang)
            showPDFError = true
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TierTap-User-Guide.pdf")
        do {
            try data.write(to: url, options: .atomic)
            pdfShareURL = url
            isPresentingPDFShare = true
        } catch {
            pdfErrorMessage = error.localizedDescription
            showPDFError = true
        }
    }
}
