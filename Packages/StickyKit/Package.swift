// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StickyKit",
    platforms: [
        .macOS("27.0"),
    ],
    products: [
        .library(name: "StickyDomain", targets: ["StickyDomain"]),
        .library(name: "StickyStorage", targets: ["StickyStorage"]),
        .library(name: "StickyUI", targets: ["StickyUI"]),
        .library(name: "StickyIntents", targets: ["StickyIntents"]),
    ],
    targets: [
        // What a sticky is and what keeping one means. Foundation only, so
        // the rules are tested without a window or a disk.
        .target(name: "StickyDomain"),
        // One file per sticky, and the announcement that one changed.
        .target(
            name: "StickyStorage",
            dependencies: ["StickyDomain"]
        ),
        // The windows: one glass panel per sticky, kept equal to the store.
        .target(
            name: "StickyUI",
            dependencies: [
                "StickyDomain",
                "StickyStorage",
            ]
        ),
        // What Spotlight, Siri and Shortcuts can ask for. Depends on the UI
        // because every intent ends in a window, and windows exist only in
        // the app process.
        .target(
            name: "StickyIntents",
            dependencies: ["StickyUI"]
        ),
        .testTarget(
            name: "StickyDomainTests",
            dependencies: ["StickyDomain"]
        ),
        .testTarget(
            name: "StickyStorageTests",
            dependencies: [
                "StickyDomain",
                "StickyStorage",
            ]
        ),
        .testTarget(
            name: "StickyUITests",
            dependencies: [
                "StickyDomain",
                "StickyStorage",
                "StickyUI",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
