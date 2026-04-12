import UIKit
import CoreText

enum UserGuidePDFExporter {
    /// Renders multi-page letter-size PDF from plain text (black on white).
    static func makePDF(text: String, title: String) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 48
        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageRect.width - 2 * margin,
            height: pageRect.height - 2 * margin
        )

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.paragraphSpacing = 6

        let titleAttr = NSAttributedString(
            string: title + "\n\n",
            attributes: [
                .font: UIFont.boldSystemFont(ofSize: 20),
                .paragraphStyle: paragraph
            ]
        )
        let bodyAttr = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 11),
                .paragraphStyle: paragraph
            ]
        )
        let full = NSMutableAttributedString()
        full.append(titleAttr)
        full.append(bodyAttr)

        let path = CGPath(rect: textRect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(full as CFAttributedString)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = pageRect
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        var pageStart: CFIndex = 0
        let stringLength = full.length

        while pageStart < stringLength {
            pdfContext.beginPDFPage(nil)
            pdfContext.saveGState()
            pdfContext.translateBy(x: 0, y: pageRect.height)
            pdfContext.scaleBy(x: 1, y: -1)

            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRangeMake(pageStart, 0),
                path,
                nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            CTFrameDraw(frame, pdfContext)

            pdfContext.restoreGState()
            pdfContext.endPDFPage()
            pageStart = visible.location + visible.length
        }

        pdfContext.closePDF()
        return data as Data
    }
}
