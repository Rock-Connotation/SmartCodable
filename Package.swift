// swift-tools-version: 5.9
import CompilerPluginSupport
import PackageDescription

#if compiler(>=6.3)
let swiftSyntaxVersion: Version = "603.0.0"
#elseif compiler(>=6.2)
let swiftSyntaxVersion: Version = "602.0.0"
#elseif compiler(>=6.1)
let swiftSyntaxVersion: Version = "601.0.0"
#elseif compiler(>=6.0)
let swiftSyntaxVersion: Version = "600.0.0"
#elseif compiler(>=5.10)
let swiftSyntaxVersion: Version = "510.0.0"
#else
let swiftSyntaxVersion: Version = "509.0.0"
#endif

let package = Package(
    name: "SmartCodable",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macCatalyst(.v13), .visionOS(.v1)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SmartCodable",
            targets: ["SmartCodable"]
        ),
        .library(
            name: "SmartCodableInherit",
            targets: ["SmartCodableInherit"]
        )
    ],
    dependencies: [
        // SwiftSyntax major versions track Swift compiler versions (e.g. 602.x for Swift 6.2).
        // Pick the matching range so SwiftPM doesn't pull a prebuilt macro support module from a
        // different compiler version (which fails to import).
        .package(url: "https://github.com/swiftlang/swift-syntax", from: swiftSyntaxVersion)
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "SmartCodableMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(
            name: "SmartCodable",
            exclude: ["MacroSupport"]),
        
        .target(
            name: "SmartCodableInherit",
            dependencies: [
                "SmartCodableMacros"
            ],
            path: "Sources/SmartCodable/MacroSupport"),
        
        // A test target used to develop the macro implementation.
        .testTarget(
            name: "SmartCodableTests",
            dependencies: [
                "SmartCodable",
                "SmartCodableInherit",
                "SmartCodableMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
