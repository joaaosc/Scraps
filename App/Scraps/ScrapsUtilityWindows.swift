import AppKit
import StickyDomain
import StickyEditor
import StickyUI
import SwiftUI

/// A single instance of each utility, available even when no note is open.
@MainActor
final class ScrapsUtilityWindows {
    static let shared = ScrapsUtilityWindows()
    private var settings: NSWindowController?
    private var colors: NSWindowController?
    private var library: NSWindowController?
    private var deleted: NSWindowController?

    func configure() {
        StickyBoard.shared.showSettingsHandler = { [weak self] in self?.showSettings() }
        StickyBoard.shared.showColorPickerHandler = { [weak self] in self?.showColors() }
    }

    func showLibrary() {
        if library == nil {
            library = makeWindow(title: "Scraps", size: CGSize(width: 860, height: 540)) { ScrapsLibraryView() }
        }
        show(library)
    }

    func showSettings() {
        if settings == nil {
            settings = makeWindow(title: String(localized: "Settings"), size: CGSize(width: 480, height: 480)) {
                ScrapsSettingsView()
            }
        }
        show(settings)
    }

    func showColors() {
        if colors == nil {
            colors = makeWindow(title: String(localized: "New Sticky in Color…"), size: CGSize(width: 340, height: 180)) {
                ScrapsNewColorView(onCreated: { [weak self] in self?.colors?.close() })
            }
        }
        show(colors)
    }

    func showRecentlyDeleted() {
        if deleted == nil {
            deleted = makeWindow(title: String(localized: "Recently Deleted"), size: CGSize(width: 480, height: 420)) {
                ScrapsRecentlyDeletedView()
            }
        }
        show(deleted)
    }

    private func makeWindow<Content: View>(title: String, size: CGSize, @ContentBuilder content: () -> Content) -> NSWindowController {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        window.contentViewController = NSHostingController(rootView: content())
        window.center()
        return NSWindowController(window: window)
    }

    private func show(_ controller: NSWindowController?) {
        NSApplication.shared.activate()
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
    }
}
