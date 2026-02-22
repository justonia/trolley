// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "trolley",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(
            name: "CGhostty",
            path: "Sources/CGhostty"
        ),
        .systemLibrary(
            name: "CTrolley",
            path: "Sources/CTrolley"
        ),
        .executableTarget(
            name: "trolley",
            dependencies: ["CGhostty", "CTrolley"],
            path: "Sources",
            exclude: ["CGhostty", "CTrolley"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
