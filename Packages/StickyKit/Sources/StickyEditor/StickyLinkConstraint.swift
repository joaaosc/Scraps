import Foundation
import StickyDomain
import SwiftUI

struct StickyLinkConstraint: AttributedTextValueConstraint {
    typealias Scope = StickyFormattingScope
    typealias AttributeKey = AttributeScopes.FoundationAttributes.LinkAttribute
    func constrain(_ container: inout Attributes) {
        container.link = StickyTextRun.safeLink(container.link)
    }
}
