import Foundation
import SwiftUI

struct StickyFormattingDefinition: AttributedTextFormattingDefinition {
    let context: Font.Context
    var body: some AttributedTextFormattingDefinition<StickyFormattingScope> {
        StickyFontConstraint(context: context)
        StickyLinkConstraint()
        ValueConstraint(for: AttributeScopes.SwiftUIAttributes.FontAttribute.self, values: StickyRichTextBridge.supportedFonts, default: .body)
        ValueConstraint(for: AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self, values: [nil, .single], default: .single)
        ValueConstraint(for: AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute.self, values: [nil, .single], default: .single)
        ValueConstraint(for: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self, values: [nil, .yellow.opacity(0.28)], default: .yellow.opacity(0.28))
    }
}
