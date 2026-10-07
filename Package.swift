// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScaleBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ScaleBarCore", path: "Sources/ScaleBarCore"),
        .executableTarget(
            name: "ScaleBar",
            dependencies: ["ScaleBarCore"],
            path: "Sources/ScaleBar",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "ScaleBarTests", dependencies: ["ScaleBarCore"], path: "Tests/ScaleBarTests"),
    ]
)
