import AppKit

/// One system sharing request. Delegate callbacks belong to this request even
/// if a newer request has already replaced it in the same sticky window.
@MainActor
final class NotesShareOperation: NSObject, NSSharingServiceDelegate, @MainActor NSSharingServicePickerDelegate {
    private weak var window: NSWindow?
    private let route: NotesSharingAvailability.Route
    private var completion: ((NotesSharingAvailability.Outcome) -> Void)?
    private var service: NSSharingService?
    private var picker: NSSharingServicePicker?

    init(
        window: NSWindow? = nil,
        route: NotesSharingAvailability.Route,
        completion: @escaping (NotesSharingAvailability.Outcome) -> Void
    ) {
        self.window = window
        self.route = route
        self.completion = completion
    }

    func use(_ service: NSSharingService) {
        self.service = service
        service.delegate = self
    }

    func use(_ picker: NSSharingServicePicker) {
        self.picker = picker
        picker.delegate = self
    }

    func cancel() { finish(with: .cancelled) }

    func failToOpenPicker() {
        finish(with: .failed(String(localized: "Could not open the sharing menu.", bundle: .module)))
    }

    private func finish(with outcome: NotesSharingAvailability.Outcome) {
        let completion = completion
        self.completion = nil
        service?.delegate = nil
        picker?.delegate = nil
        service = nil
        picker = nil
        completion?(outcome)
    }

    func sharingService(
        _ sharingService: NSSharingService,
        sourceWindowForShareItems items: [Any],
        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        guard sharingService === service else { return nil }
        return window
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard sharingService === service else { return }
        finish(with: .sent(route))
    }

    func sharingService(
        _ sharingService: NSSharingService,
        didFailToShareItems items: [Any],
        error: Error
    ) {
        guard sharingService === service else { return }
        finish(with: NotesSharingAvailability.outcome(for: error, route: route))
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        delegateFor sharingService: NSSharingService
    ) -> (any NSSharingServiceDelegate)? {
        guard sharingServicePicker === picker else { return nil }
        use(sharingService)
        return self
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        guard sharingServicePicker === picker else { return }
        if let service {
            use(service)
        } else {
            finish(with: .cancelled)
        }
    }
}
