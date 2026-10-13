import CoreTransferable
import Foundation
import StickyDomain
import UniformTypeIdentifiers

public struct StickyShareDocument: Transferable, Sendable {
    public let sticky: Sticky
    public init(sticky: Sticky) { self.sticky = sticky }
    public var plainText: String { sticky.text }
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .rtf) { document in
            try await MainActor.run {
                let text = StickyRichTextBridge.foundationText(text: document.sticky.text, richText: document.sticky.richText)
                return try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            }
        }
        .suggestedFileName { document in
            let title = document.sticky.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            return String(title.prefix(80))
        }
        ProxyRepresentation(exporting: \.plainText)
    }
}
