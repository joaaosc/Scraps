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
    ],
    swiftLanguageModes: [.v6]
)
