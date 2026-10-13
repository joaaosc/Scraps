import Foundation
import SwiftUI

/// Converts imported fonts to system body text while keeping their emphasis.
struct StickyFontConstraint: AttributedTextValueConstraint {
    typealias Scope = StickyFormattingScope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.FontAttribute

    let context: Font.Context

    func constrain(_ container: inout Attributes) {
        guard let font = container.font else { return }
        let emphasis = StickyRichTextBridge.emphasis(of: font, in: context)
        container.font = StickyRichTextBridge.canonicalFont(
            bold: emphasis.bold, italic: emphasis.italic
        )
    }
}
