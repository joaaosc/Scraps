import AppKit
import StickyDomain
import StickyEditor

/// Hands a sticky's text to Apple Notes through the system's sharing service.
///
/// Apple's own sheet asks the person to confirm, which is intended; the
/// service gives nothing back and nothing is read from Notes. No Apple Event,
/// URL scheme or entitlement is involved.
///
/// When the Notes service is missing or refuses the text, the system's sharing
/// picker is offered instead and the result is not described as Notes.
@MainActor
final class NotesSharer {
    /// Owns the request and its service/picker until the system finishes it.
    private var operation: NotesShareOperation?

    /// - Parameters:
    ///   - anchor: where the sending button is, in the window's content
    ///     coordinates, for the fallback picker to point at.
    ///   - completion: called once, on the main actor, when the share ends.
    func share(
        _ text: String,
        richText: StickyRichText? = nil,
        from window: NSWindow,
        anchor: CGRect,
        completion: @escaping (NotesSharingAvailability.Outcome) -> Void
    ) {
        operation?.cancel()

        // A non-activating panel is fragile as a sharing source: the sheet
        // needs the window to be key, and that needs the app to be active.
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)

        let service = NSSharingService(
            named: NSSharingService.Name(NotesSharingAvailability.serviceName)
        )
        let attributedText = StickyRichTextBridge.foundationText(text: text, richText: richText)
        // Some extensions accept attributed text, while others only take a
        // string. Prefer the native rich item when the service can handle it.
        let richItems: [Any] = [attributedText]
        let plainItems: [Any] = [text]
        let items = richText != nil && (service?.canPerform(withItems: richItems) ?? false)
            ? richItems : plainItems
        let route = NotesSharingAvailability.route(
            serviceFound: service != nil,
            canPerformWithText: service?.canPerform(withItems: items) ?? false
        )
        let operation = NotesShareOperation(window: window, route: route, completion: completion)
        self.operation = operation

        switch route {
        case .notes:
            guard let service else { return }
            operation.use(service)
            service.perform(withItems: items)
        case .picker:
            let picker = NSSharingServicePicker(items: richText == nil ? plainItems : richItems)
            operation.use(picker)
            if let contentView = window.contentView {
                // Content coordinates are flipped relative to AppKit's.
                let flipped = CGRect(
                    x: anchor.minX,
                    y: contentView.bounds.height - anchor.maxY,
                    width: anchor.width,
                    height: anchor.height
                )
                picker.show(relativeTo: flipped, of: contentView, preferredEdge: .minY)
            } else {
                operation.failToOpenPicker()
            }
        }
    }

}
