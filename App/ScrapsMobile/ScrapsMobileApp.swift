import AppIntents
import CoreSpotlight
import Foundation
import OSLog
import StickyDomain
import StickyIntents
import StickyMobileUI
import StickyStorage
import SwiftUI

struct ScrapsMobileIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [StickyIntentsPackage.self]
    }
}

@main
@MainActor
struct ScrapsMobileApp: App {
    @State private var library: MobileStickyLibrary

    private static let logger = Logger(
        subsystem: StickyKitIdentity.bundleIdentifier,
        category: "MobileApp"
    )

    init() {
        UserDefaults.standard.register(defaults: [
            "defaultStickyColor": StickyColor.clear.rawValue,
            "mobileShowsList": false,
        ])
        let library: MobileStickyLibrary
        do {
            let durable = try FileStickyStore()
            library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
        } catch {
            Self.logger.error("Could not open the stickies folder: \(error.localizedDescription, privacy: .public)")
            library = MobileStickyLibrary(error: error)
        }
        _library = State(initialValue: library)
        StickyActionRouter.handler = { action, text, color in
            switch action {
            case .newSticky, .newSessionSticky:
                library.presentation = nil
                guard let sticky = await library.newSticky(
                    text: text ?? "",
                    sessionOnly: action == .newSessionSticky,
                    color: color
                ) else {
                    throw StickyActionRoutingError.appUnavailable
                }
                library.openSticky(id: sticky.id)
            case .newStickyInColor:
                library.presentation = .colorPicker
            case .settings:
                library.presentation = .settings
            }
        }
        StickyActionRouter.showAllHandler = {
            library.showAll()
        }
    }

    var body: some Scene {
        WindowGroup {
            MobileStickyRootView(library: library)
                .task {
                    do {
                        try await StickyActionIndex.rebuild()
                    } catch {
                        Self.logger.error("Could not update Spotlight actions: \(error.localizedDescription, privacy: .public)")
                    }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let action = StickyActionEntity.action(from: activity) else { return }
                    Task {
                        do {
                            try await StickyActionRouter.perform(action)
                        } catch {
                            library.notice = MobileStickyNotice(message: error.localizedDescription)
                        }
                    }
                }
        }
    }
}
