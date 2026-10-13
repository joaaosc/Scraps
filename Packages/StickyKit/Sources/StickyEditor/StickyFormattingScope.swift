import Foundation
import SwiftUI

struct StickyFormattingScope: AttributeScope {
    let font: AttributeScopes.SwiftUIAttributes.FontAttribute
    let underlineStyle: AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
    let strikethroughStyle: AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute
    let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
    let link: AttributeScopes.FoundationAttributes.LinkAttribute
}
