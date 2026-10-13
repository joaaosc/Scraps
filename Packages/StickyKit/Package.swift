// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "StickyDomain", targets: ["StickyDomain"]),
    .library(name: "StickyStorage", targets: ["StickyStorage"]),
]
var targets: [Target] = [
    .target(name: "StickyDomain", resources: [.process("Resources")]),
    .target(name: "StickyStorage", dependencies: ["StickyDomain"], resources: [.process("Resources")]),
    .testTarget(name: "StickyDomainTests", dependencies: ["StickyDomain"]),
    .testTarget(name: "StickyStorageTests", dependencies: ["StickyDomain", "StickyStorage"]),
]

// Linux runs the same data and migration tests. Xcode builds native targets.
#if os(Linux)
products += [.library(name: "StickyMobileUI", targets: ["StickyMobileUI"])]
targets += [
    .target(name: "StickyMobileUI", dependencies: ["StickyDomain", "StickyStorage"], exclude: ["MobileBackgroundSave.swift", "MobileNewColorView.swift", "MobileRecentlyDeletedView.swift", "MobileStickyCard.swift", "MobileStickyDetailView.swift", "MobileStickyRootView.swift", "MobileStickyRow.swift", "MobileStickySettingsView.swift", "MobileStickyShareDocument.swift", "Sticky+MobilePreview.swift", "StickyColor+MobileSurface.swift"], sources: ["MobileStickyLibrary.swift"], resources: [.process("Resources")]),
    .testTarget(name: "StickyMobileUITests", dependencies: ["StickyDomain", "StickyStorage", "StickyMobileUI"]),
]
#else
products += [
    .library(name: "StickyEditor", targets: ["StickyEditor"]),
    .library(name: "StickyUI", targets: ["StickyUI"]),
    .library(name: "StickyIntents", targets: ["StickyIntents"]),
    .library(name: "StickyMobileUI", targets: ["StickyMobileUI"]),
    .library(name: "StickySync", targets: ["StickySync"]),
]
targets += [
    .target(name: "StickyEditor", dependencies: ["StickyDomain"], resources: [.process("Resources")]),
    .target(name: "StickyUI", dependencies: ["StickyDomain", "StickyStorage", "StickyEditor"], resources: [.process("Resources")]),
    .target(name: "StickyIntents", dependencies: [
        "StickyDomain",
        .target(name: "StickyUI", condition: .when(platforms: [.macOS])),
    ], resources: [.process("Resources")]),
    .target(name: "StickySync", dependencies: ["StickyDomain", "StickyStorage"], resources: [.process("Resources")]),
    .target(name: "StickyMobileUI", dependencies: ["StickyDomain", "StickyStorage", "StickyEditor", "StickySync"], resources: [.process("Resources")]),
    .testTarget(name: "StickyEditorTests", dependencies: ["StickyDomain", "StickyEditor"]),
    .testTarget(name: "StickyUITests", dependencies: ["StickyDomain", "StickyStorage", "StickyUI"]),
    .testTarget(name: "StickyIntentsTests", dependencies: ["StickyDomain", "StickyIntents"]),
    .testTarget(name: "StickyMobileUITests", dependencies: ["StickyDomain", "StickyStorage", "StickyMobileUI"]),
]
#endif

let package = Package(
    name: "StickyKit",
    defaultLocalization: "en",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
