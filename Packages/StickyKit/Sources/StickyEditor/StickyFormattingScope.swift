import Foundation
import SwiftUI

/// Restricts the native editor to the emphasis supported by portable notes.
struct StickyFormattingScope: AttributeScope {
    let font: AttributeScopes.SwiftUIAttributes.FontAttribute
}
