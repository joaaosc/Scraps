import Carbon
import Foundation

/// Carbon registers one explicit shortcut with the window server; it does not
/// observe keystrokes or require Accessibility or Input Monitoring access.
final class StickyGlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor @Sendable () -> Void

    struct RegistrationError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            String(format: String(localized: "Control–Option–Command–N could not be registered (%d). It may already be used by another app.", bundle: .module), status)
        }
    }

    @MainActor
    init(action: @escaping @MainActor @Sendable () -> Void) throws {
        self.action = action
        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let shortcut = Unmanaged<StickyGlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                let action = shortcut.action
                Task { @MainActor in action() }
                return noErr
            },
            1, &specification, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard installed == noErr else { throw RegistrationError(status: installed) }
        let registered = RegisterEventHotKey(
            UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: OSType(0x53435250), id: 1),
            GetApplicationEventTarget(), 0, &hotKey
        )
        guard registered == noErr else {
            if let handler { RemoveEventHandler(handler) }
            handler = nil
            throw RegistrationError(status: registered)
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
