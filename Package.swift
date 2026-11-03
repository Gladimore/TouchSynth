// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "TouchSynth",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "TouchSynth", targets: ["TouchSynth"]),
    ],
    targets: [
        .target(
            name: "TouchSynth",
            path: "Sources/TouchSynth",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
    ]
)
