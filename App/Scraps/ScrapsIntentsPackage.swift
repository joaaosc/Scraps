import AppIntents
import StickyIntents

struct ScrapsIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [StickyIntentsPackage.self] }
}
