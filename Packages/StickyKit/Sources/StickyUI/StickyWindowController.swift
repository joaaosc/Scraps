import AppKit
import StickyDomain
import SwiftUI

/// One sticky's window: a glass panel holding the text and its controls.
@MainActor
final class StickyWindowController: NSObject, NSWindowDelegate {
    let model: StickyModel
    private let panel: StickyGlassPanel
    private let sharer = NotesSharer()
    private let onClosed: @MainActor (UUID) -> Void
    private var isClosed = false

    /// - Parameters:
    ///   - cascadeSlot: how many stickies are already open, so this one does
    ///     not land exactly on top of another.
    ///   - onClosed: told when the window is gone, however it went.
    init(
        sticky: Sticky,
        store: any StickyStore,
        cascadeSlot: Int,
        startsFocused: Bool,
        onClosed: @escaping @MainActor (UUID) -> Void
    ) {
        self.onClosed = onClosed

        let frame = StickyPlacement.frame(
            stored: sticky.frame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            cascadeSlot: cascadeSlot
        )
        let panel = StickyGlassPanel(contentRect: frame)
        self.panel = panel

        // The model's dependencies reach the window and the sharer, which do
        // not exist until `self` does; the box lets them be wired afterwards.
        let box = WindowBox()
        model = StickyModel(
            sticky: sticky,
            startsFocused: startsFocused,
            dependencies: StickyModel.Dependencies(
                save: { try await store.save($0) },
                delete: { try await store.delete(id: $0) },
                share: { text, anchor, completion in
                    guard let controller = box.controller else {
                        completion(.cancelled)
                        return
                    }
                    controller.sharer.share(
                        text,
                        from: controller.panel,
                        anchor: anchor,
                        completion: completion
                    )
                },
                closeWindow: { box.controller?.closeNow() },
                applyLevel: { box.controller?.applyLevel(floatsOnTop: $0) },
                copyToPasteboard: { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            )
        )
        super.init()
        box.controller = self

        panel.identifier = NSUserInterfaceItemIdentifier("sticky-\(sticky.id.uuidString)")
        panel.title = "Sticky"
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = StickyPlacement.minimumSize
        applyLevel(floatsOnTop: sticky.floatsOnTop)
        panel.contentView = StickyGlassHostingView(
            rootView: StickyView(model: model).stickyGlassSurface()
        )
        panel.invalidateShadow()
        // After the first placement: setting the frame above must not look like
        // the person moving the window.
        panel.delegate = self
        if sticky.frame == nil {
            model.frameDidChange(Self.stickyFrame(of: panel))
        }
    }

    var id: UUID { model.id }

    /// Puts the window on screen. A sticky the person just made takes the
    /// keyboard; one that arrives from elsewhere is shown without stealing it.
    func show(takingKeyboard: Bool) {
        if takingKeyboard {
            NSApplication.shared.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Closes the window without touching the stored sticky. Used when the
    /// sticky is already gone, or when the window is simply being retired.
    func closeNow() {
        guard !isClosed else { return }
        isClosed = true
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
        onClosed(id)
    }

    private func applyLevel(floatsOnTop: Bool) {
        panel.isFloatingPanel = floatsOnTop
        panel.level = floatsOnTop ? .floating : .normal
    }

    private static func stickyFrame(of window: NSWindow) -> StickyFrame {
        let frame = window.frame
        return StickyFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height
        )
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        model.frameDidChange(Self.stickyFrame(of: panel))
    }

    func windowDidResize(_ notification: Notification) {
        model.frameDidChange(Self.stickyFrame(of: panel))
    }

    /// Closing a sticky deletes it, so the window's own close (Command-W) goes
    /// through the same question as the button.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.requestClose()
        return false
    }
}

/// A forward reference, so closures given to the model can reach a controller
/// that is built after it.
@MainActor
private final class WindowBox {
    weak var controller: StickyWindowController?
}
