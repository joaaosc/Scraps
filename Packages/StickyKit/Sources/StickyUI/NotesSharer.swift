import AppKit

/// Hands a sticky's text to Apple Notes through the system's sharing service.
///
/// Apple's own sheet asks the person to confirm, which is intended; the
/// service gives nothing back and nothing is read from Notes. No Apple Event,
/// URL scheme or entitlement is involved.
///
/// When the Notes service is missing or refuses the text, the system's sharing
/// picker is offered instead and the result is not described as Notes.
@MainActor
final class NotesSharer: NSObject, NSSharingServiceDelegate, @MainActor NSSharingServicePickerDelegate {
    private weak var window: NSWindow?
    private var route: NotesSharingAvailability.Route = .notes
    private var completion: ((NotesSharingAvailability.Outcome) -> Void)?
    /// Held until the share ends: both are released by AppKit as soon as
    /// nothing references them, which would close the sheet.
    private var activeService: NSSharingService?
    private var activePicker: NSSharingServicePicker?

    /// - Parameters:
    ///   - anchor: where the sending button is, in the window's content
    ///     coordinates, for the fallback picker to point at.
    ///   - completion: called once, on the main actor, when the share ends.
    func share(
        _ text: String,
        from window: NSWindow,
        anchor: CGRect,
        completion: @escaping (NotesSharingAvailability.Outcome) -> Void
    ) {
        finish(with: .cancelled)
        self.window = window
        self.completion = completion

        // A non-activating panel is fragile as a sharing source: the sheet
        // needs the window to be key, and that needs the app to be active.
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)

        let service = NSSharingService(
            named: NSSharingService.Name(NotesSharingAvailability.serviceName)
        )
        route = NotesSharingAvailability.route(
            serviceFound: service != nil,
            canPerformWithText: service?.canPerform(withItems: [text]) ?? false
        )

        switch route {
        case .notes:
            guard let service else { return }
            service.delegate = self
            activeService = service
            service.perform(withItems: [text])
        case .picker:
            let picker = NSSharingServicePicker(items: [text])
            picker.delegate = self
            activePicker = picker
            if let contentView = window.contentView {
                // Content coordinates are flipped relative to AppKit's.
                let flipped = CGRect(
                    x: anchor.minX,
                    y: contentView.bounds.height - anchor.maxY,
                    width: anchor.width,
                    height: anchor.height
                )
                picker.show(relativeTo: flipped, of: contentView, preferredEdge: .minY)
            }
        }
    }

    private func finish(with outcome: NotesSharingAvailability.Outcome) {
        let completion = completion
        self.completion = nil
        activeService = nil
        activePicker = nil
        completion?(outcome)
    }

    // MARK: NSSharingServiceDelegate

    func sharingService(
        _ sharingService: NSSharingService,
        sourceWindowForShareItems items: [Any],
        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        window
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish(with: .sent(route))
    }

    func sharingService(
        _ sharingService: NSSharingService,
        didFailToShareItems items: [Any],
        error: Error
    ) {
        finish(with: NotesSharingAvailability.outcome(for: error, route: route))
    }

    // MARK: NSSharingServicePickerDelegate

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        delegateFor sharingService: NSSharingService
    ) -> (any NSSharingServiceDelegate)? {
        self
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        // Choosing a service hands control to its own delegate callbacks above.
        if service == nil {
            finish(with: .cancelled)
        }
    }
}
