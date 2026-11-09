// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bando",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BandoCore", targets: ["BandoCore"]),
        .executable(name: "bando", targets: ["bando"]),
        .executable(name: "BandoApp", targets: ["BandoApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", .upToNextMinor(from: "0.6.0")),
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMinor(from: "7.11.1")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.8.2")),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", .upToNextMinor(from: "1.99.2")),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", .upToNextMinor(from: "2.10.1")),
    ],
    targets: [
        .target(
            name: "BandoCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "bando",
            dependencies: [
                "BandoCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "BandoApp",
            dependencies: [
                "BandoCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                // Sparkle.framework fica em Bando.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "BandoCoreTests",
            dependencies: ["BandoCore"]
        ),
    ]
)
