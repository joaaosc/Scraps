#if os(iOS)
import CoreTransferable
import Foundation
import StickyDomain
import UIKit
import UniformTypeIdentifiers

/// Offer rich text first and ordinary text as a fallback. Receivers such as
/// Notes can keep emphasis, while apps accepting only text get the same words.
struct MobileStickyShareDocument: Transferable, Sendable {
    let sticky: Sticky
    var plainText: String { sticky.text }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .rtf) { document in
            try await document.rtfData()
        }
        ProxyRepresentation(exporting: \.plainText)
    }

    @MainActor
    func rtfData() throws -> Data {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let attributed = NSMutableAttributedString(string: sticky.text, attributes: [.font: font])
        for run in sticky.richText?.normalized(for: sticky.text).runs ?? [] {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.bold { traits.insert(.traitBold) }
            if run.italic { traits.insert(.traitItalic) }
            guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { continue }
            attributed.addAttribute(
                .font,
                value: UIFont(descriptor: descriptor, size: font.pointSize),
                range: NSRange(location: run.location, length: run.length)
            )
        }
        return try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
#endif
