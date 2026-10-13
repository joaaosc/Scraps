import AppKit

/// A floating panel with no visible chrome, so the SwiftUI surface inside owns
/// the whole shape.
///
/// `.titled` and `.fullSizeContentView` are kept rather than dropping to
/// `.borderless`: they are what keeps the panel able to become key and
/// resizable by its edges, and the titlebar is hidden instead of absent. The
/// title itself stays set, because the Window menu and VoiceOver still read it.
///
/// Pressing in the panel brings the app forward. A sticky's commands live in
/// the menu bar, and the menu bar belongs to the active app.
public final class StickyGlassPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // The traffic lights would sit on top of the glass with nothing to
        // anchor them; the sticky's own controls close it.
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .forEach { standardWindowButton($0)?.isHidden = true }
    }

    /// A titled panel can already be key. Stated explicitly because the panel
    /// is where the person types and must never silently lose the keyboard.
    public override var canBecomeKey: Bool { true }
}
