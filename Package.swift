// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "SmartCodable",
    // This manifest is intentionally kept macro-free so older SwiftPM versions
    // can still build the runtime library without pulling in swift-syntax.
    //
    // SwiftPM will automatically pick `Package@swift-5.9.swift` on Swift 5.9+,
    // where macro targets and swift-syntax dependencies are defined.
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SmartCodable",
            targets: ["SmartCodable"]
        )
    ],
    targets: [
        .target(
            name: "SmartCodable",
            exclude: ["MacroSupport"]),
    ]
)
