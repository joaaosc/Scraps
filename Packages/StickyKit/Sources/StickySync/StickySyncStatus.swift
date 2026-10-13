import Foundation

public enum StickySyncStatus: Equatable, Sendable {
    case disabled
    case syncing
    case upToDate
    case notSignedIn
    case accountChanged
    case failed(String)
}
