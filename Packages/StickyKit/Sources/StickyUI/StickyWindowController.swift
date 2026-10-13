import AppKit
import StickyDomain
import StickyStorage
import StickyEditor
import SwiftUI

/// A native panel per note, including Window-menu registration and reversible
/// collapse. The persisted frame always describes the expanded note.
@MainActor
final class StickyWindowController: NSObject, NSWindowDelegate {
    let model: StickyModel
    private let panel: StickyGlassPanel
    private let sharer = NotesSharer()
    private let onClosed: @MainActor (UUID) -> Void
    private let onActivated: @MainActor (UUID) -> Void
    private let onDeactivated: @MainActor (UUID) -> Void
    private var isClosed = false
    private var isApplyingFrame = false
    private var expandedFrame: CGRect

    init(
        sticky: Sticky,
        store: any StickyStore,
        cascadeSlot: Int,
        startsFocused: Bool,
        isSessionOnly: Bool = false,
        onActivated: @escaping @MainActor (UUID) -> Void = { _ in },
        onDeactivated: @escaping @MainActor (UUID) -> Void = { _ in },
        onClosed: @escaping @MainActor (UUID) -> Void
    ) {
        self.onClosed = onClosed
        self.onActivated = onActivated
        self.onDeactivated = onDeactivated
        let frame = StickyPlacement.frame(
            stored: sticky.frame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            cascadeSlot: cascadeSlot
        )
        expandedFrame = frame
        let panel = StickyGlassPanel(contentRect: frame)
        self.panel = panel
        // Placement is a window frame, not a content rect. Explicitly set it
        // to avoid adding the hidden title bar again on every launch.
        panel.setFrame(frame, display: false)
        let box = WindowBox()
        model = StickyModel(
            sticky: sticky,
            startsFocused: startsFocused,
            isSessionOnly: isSessionOnly,
            dependencies: StickyModel.Dependencies(
                save: { try await store.save($0) },
                delete: { try await store.delete(id: $0) },
                share: { text, anchor, completion in
                    guard let controller = box.controller else { completion(.cancelled); return }
                    controller.sharer.share(text, from: controller.panel, anchor: anchor, completion: completion)
                },
                closeWindow: { box.controller?.closeNow() },
                applyLevel: { box.controller?.applyLevel(floatsOnTop: $0) },
                copyToPasteboard: { StickyRichTextBridge.copyToPasteboard(text: $0, richText: nil) },
                moveToTrash: { sticky in
                    if let recoverable = store as? any RecentlyDeletedStickyStore {
                        try await recoverable.moveToTrash(sticky, at: Date())
                    } else {
                        try await store.delete(id: sticky.id)
                    }
                },
                shareRichText: { text, richText, anchor, completion in
                    guard let controller = box.controller else { completion(.cancelled); return }
                    controller.sharer.share(
                        text, richText: richText, from: controller.panel,
                        anchor: anchor, completion: completion
                    )
                },
                copyRichText: { StickyRichTextBridge.copyToPasteboard(text: $0, richText: $1) },
                applyCollapsed: { box.controller?.applyCollapsed($0) },
                applyAllSpaces: { box.controller?.applyAllSpaces($0) },
                applyColor: { box.controller?.applyColor($0) },
                updateTitle: { box.controller?.updateTitle($0) },
                saveCompared: { note, previous in
                    if let files = store as? FileStickyStore {
                        try await files.applySynchronized(note, replacing: previous)
                    } else { try await store.save(note) }
                }
            )
        )
        super.init()
        box.controller = self
        panel.identifier = NSUserInterfaceItemIdentifier("sticky-\(sticky.id.uuidString)")
        panel.title = model.title
        panel.isExcludedFromWindowsMenu = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = StickyPlacement.minimumSize
        applyLevel(floatsOnTop: sticky.floatsOnTop)
        applyAllSpaces(sticky.appearsOnAllSpaces)
        panel.contentView = StickyGlassHostingView(rootView: StickyView(model: model).ignoresSafeArea().stickyGlassSurface())
        applyColor(sticky.color)
        if sticky.isCollapsed { applyCollapsed(true) }
        panel.invalidateShadow()
        panel.delegate = self
        NSApplication.shared.addWindowsItem(panel, title: model.title, filename: false)
        model.frameDidChange(Self.stickyFrame(frame))
    }

    var id: UUID { model.id }

    func show(takingKeyboard: Bool) {
        if takingKeyboard {
            NSApplication.shared.activate()
            panel.makeKeyAndOrderFront(nil)
            onActivated(id)
        } else {
            panel.orderFrontRegardless()
        }
        NSApplication.shared.addWindowsItem(panel, title: model.title, filename: false)
    }

    func closeNow() {
        guard !isClosed else { return }
        isClosed = true
        panel.delegate = nil
        NSApplication.shared.removeWindowsItem(panel)
        panel.orderOut(nil)
        panel.close()
        onClosed(id)
    }

    func shareCollection(_ text: String) {
        sharer.share(text, from: panel, anchor: model.sendButtonFrame) { outcome in
            if case let .failed(message) = outcome {
                let alert = NSAlert()
                alert.messageText = String(localized: "Could not send the stickies to Notes", bundle: .module)
                alert.informativeText = message
                alert.beginSheetModal(for: self.panel)
            }
        }
    }

    private func applyLevel(floatsOnTop: Bool) {
        panel.isFloatingPanel = floatsOnTop
        panel.level = floatsOnTop ? .floating : .normal
    }

    private func applyAllSpaces(_ allSpaces: Bool) {
        // These Spaces flags are mutually exclusive. Both modes participate in
        // keyboard window cycling; all-Spaces notes may join full-screen apps.
        panel.collectionBehavior = allSpaces
            ? [.canJoinAllSpaces, .canJoinAllApplications, .participatesInCycle]
            : [.managed, .participatesInCycle]
    }

    private func applyColor(_ color: StickyColor) {
        guard let glass = panel.contentView as? NSGlassEffectView else { return }
        let tint: NSColor? = switch color {
        case .clear: nil
        case .yellow: .systemYellow
        case .blue: .systemBlue
        case .green: .systemGreen
        case .pink: .systemPink
        case .purple: .systemPurple
        case .gray: .systemGray
        }
        glass.tintColor = tint?.withAlphaComponent(0.16)
    }

    private func applyCollapsed(_ collapsed: Bool) {
        isApplyingFrame = true
        defer { isApplyingFrame = false }
        if collapsed {
            expandedFrame = panel.frame
            panel.minSize = CGSize(width: StickyPlacement.minimumSize.width, height: StickyPlacement.collapsedHeight)
            panel.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: StickyPlacement.collapsedHeight)
            panel.setFrame(StickyPlacement.collapsedFrame(expanded: expandedFrame), display: true)
        } else {
            panel.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            panel.minSize = StickyPlacement.minimumSize
            panel.setFrame(expandedFrame, display: true)
        }
        model.frameDidChange(Self.stickyFrame(expandedFrame))
    }

    private func updateTitle(_ title: String) {
        panel.title = title
        NSApplication.shared.changeWindowsItem(panel, title: title, filename: false)
        NSApplication.shared.updateWindowsItem(panel)
    }

    private func recordFrame() {
        guard !isApplyingFrame else { return }
        if model.isCollapsed {
            expandedFrame = StickyPlacement.expandedFrame(
                afterMovingCollapsed: panel.frame, previousExpanded: expandedFrame
            )
        } else {
            expandedFrame = panel.frame
        }
        model.frameDidChange(Self.stickyFrame(expandedFrame))
    }

    private static func stickyFrame(_ frame: CGRect) -> StickyFrame {
        StickyFrame(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    func windowDidMove(_ notification: Notification) { recordFrame() }
    func windowDidResize(_ notification: Notification) { recordFrame() }
    func windowDidBecomeKey(_ notification: Notification) {
        onActivated(id)
        if !model.isSessionOnly {
            panel.userActivity = StickyNavigation.handoff(for: model.snapshot)
            panel.userActivity?.becomeCurrent()
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        onDeactivated(id)
        panel.userActivity?.resignCurrent()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model.requestClose(); return false }
}

@MainActor
private final class WindowBox {
    weak var controller: StickyWindowController?
}
