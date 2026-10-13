import Foundation

/// How a sticky's text gets to Apple Notes, and how a failure is told.
///
/// The only road is the system's sharing service for Notes. It shows Apple's
/// own confirmation sheet and gives nothing back: nothing is ever read from
/// Notes and Notes is never scripted.
enum NotesSharingAvailability {
    /// The sharing extension Notes registers with the system.
    static let serviceName = "com.apple.Notes.SharingExtension"

    enum Route: Equatable {
        /// Notes' own service, straight to its confirmation sheet.
        case notes
        /// The system's list of sharing targets, because the Notes service is
        /// missing or refuses the text. What the person picks there is theirs
        /// to choose, so it is never reported as "Sent to Notes".
        case picker
    }

    enum Outcome: Equatable {
        case sent(Route)
        /// The person closed the sheet. Not a failure, nothing to report.
        case cancelled
        case failed(String)
    }

    static func route(serviceFound: Bool, canPerformWithText: Bool) -> Route {
        serviceFound && canPerformWithText ? .notes : .picker
    }

    /// Why sending is not possible right now, or nil when it is.
    static func unavailableReason(forText text: String) -> String? {
        text.allSatisfy(\.isWhitespace)
            ? "Type something first, then send it to Notes."
            : nil
    }

    static func outcome(for error: Error, route: Route) -> Outcome {
        if isUserCancellation(error) { return .cancelled }
        let subject = route == .notes ? "send this sticky to Notes" : "share this sticky"
        return .failed("Could not \(subject): \(error.localizedDescription)")
    }

    static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}
