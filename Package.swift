// swift-tools-version: 6.0
// Construction de l'app via SwiftPM (sans Xcode) : `make run`.
// VIALETKIT_PATH=../vialetkit make run : travailler sur le kit et l'app en meme temps
// (ne pas committer le Package.resolved modifie dans ce mode).
import Foundation
import PackageDescription

let kit: Package.Dependency = ProcessInfo.processInfo.environment["VIALETKIT_PATH"]
    .map { .package(path: $0) } ?? .package(url: "https://github.com/avialet/vialetkit.git", .upToNextMinor(from: "0.2.5"))

let package = Package(
    name: "LanterneApp",
    platforms: [.macOS("26.0")],
    dependencies: [
        kit,
        .package(path: "Packages/LanterneCore"),
    ],
    targets: [
        .executableTarget(
            name: "Lanterne",
            dependencies: [
                .product(name: "VialetKit", package: "vialetkit"),
                .product(name: "LanterneCore", package: "LanterneCore"),
            ],
            path: "Lanterne",
            exclude: ["Resources"]
        ),
    ]
)
