import AppIntents
import CoreSpotlight
import Foundation
import OSLog
import StickyDomain
import StickyIntents
import StickyMobileUI
import StickyStorage
import StickySync
import SwiftUI

struct ScrapsMobileIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [StickyIntentsPackage.self]
    }
}

@main
@MainActor
struct ScrapsMobileApp: App {
    @UIApplicationDelegateAdaptor(ScrapsMobileDelegate.self) private var delegate
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
            let durable = try StickyAppStorage.makeStore()
            library = MobileStickyLibrary(store: SessionStickyStore(durable: durable))
            Task { await StickyWidgetUpdates.shared.observe(durable) }
            StickyCloudSync.shared.connect(to: durable) {
                await library.flush()
                return await library.saveStates.values.allSatisfy { $0 == .saved }
            }
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
                .onContinueUserActivity(StickyKitIdentity.handoffActivityType) { activity in
                    guard let id = StickyNavigation.noteID(from: activity) else { return }
                    Task { await open(.note(id)) }
                }
                .onOpenURL { url in
                    guard let route = StickyNavigation(url: url) else { return }
                    Task { await open(route) }
                }
        }
    }

    private func open(_ route: StickyNavigation) async {
        switch route {
        case let .note(id):
            await library.reload()
            if library.sticky(id: id) == nil {
                await StickyCloudSync.shared.synchronize()
                await library.reload()
            }
            if library.sticky(id: id) != nil { library.openSticky(id: id) }
            else { library.notice = MobileStickyNotice(message: String(localized: "This note has not reached this device yet")) }
        case .new:
            if let sticky = await library.newSticky() { library.openSticky(id: sticky.id) }
        case .library: library.showAll()
        }
    }
}
