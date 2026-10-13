import SwiftUI

/// Makes a region drag its own window.
///
/// A panel with `isMovableByWindowBackground` only moves when the click lands
/// somewhere nothing else consumes it, and a sticky is a text editor that
/// fills the window. This states the grab area instead of hoping one survives,
/// and `allowsWindowActivationEvents` is what lets the drag start while
/// another app still holds activation.
struct StickyWindowDragArea: ViewModifier {
    let onDoubleClick: (() -> Void)?

    func body(content: Content) -> some View {
        content
            // Without a hit-testable shape the gesture only sees the glyphs,
            // not the empty run between them.
            .contentShape(.rect)
            .gesture(WindowDragGesture())
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                onDoubleClick?()
            })
            .allowsWindowActivationEvents(true)
    }
}

extension View {
    /// Lets this region drag the window it is in.
    func stickyWindowDrag(onDoubleClick: (() -> Void)? = nil) -> some View {
        modifier(StickyWindowDragArea(onDoubleClick: onDoubleClick))
    }
}
