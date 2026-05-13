import UIKit

enum UserGuidePDFExporter {
    /// Renders multi-page letter-size PDF from plain text (black on white).
    /// Uses `UIGraphicsPDFRenderer` + `NSLayoutManager` so coordinates match UIKit (avoids flipped / inverted Core Text + Quartz PDF output).
    static func makePDF(text: String, title: String) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 48
        let contentSize = CGSize(
            width: pageRect.width - 2 * margin,
            height: pageRect.height - 2 * margin
        )

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.paragraphSpacing = 6

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor.black
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor.black
        ]

        let full = NSMutableAttributedString(string: title + "\n\n", attributes: titleAttributes)
        full.append(NSAttributedString(string: text, attributes: bodyAttributes))

        let textStorage = NSTextStorage(attributedString: full)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { pdfContext in
            var glyphIndex = 0
            let totalGlyphs = layoutManager.numberOfGlyphs
            let drawOrigin = CGPoint(x: margin, y: margin)

            while glyphIndex < totalGlyphs {
                pdfContext.beginPage()
                let container = NSTextContainer(size: contentSize)
                container.lineFragmentPadding = 0
                layoutManager.addTextContainer(container)
                layoutManager.ensureLayout(for: container)

                let glyphRange = layoutManager.glyphRange(for: container)
                guard glyphRange.length > 0 else { break }

                layoutManager.drawBackground(forGlyphRange: glyphRange, at: drawOrigin)
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: drawOrigin)

                let next = NSMaxRange(glyphRange)
                if next <= glyphIndex { break }
                glyphIndex = next
            }
        }
        return data
    }
}
