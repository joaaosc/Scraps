import Foundation
import SwiftUI

/// The editor supports precisely the four font styles its file format keeps.
struct StickyFormattingDefinition: AttributedTextFormattingDefinition {
    let context: Font.Context

    var body: some AttributedTextFormattingDefinition<StickyFormattingScope> {
        StickyFontConstraint(context: context)
        ValueConstraint(
            for: AttributeScopes.SwiftUIAttributes.FontAttribute.self,
            values: [nil, .body, .body.bold(), .body.italic(), .body.bold().italic()],
            default: .body
        )
    }
}
