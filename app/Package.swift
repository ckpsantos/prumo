// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Assistente",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "Assistente", path: "Sources/Assistente",
                          linkerSettings: [.linkedLibrary("sqlite3")])
    ]
)
