// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BudsControl", defaultLocalization: "en", platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BudsApp", path: "Sources",
            exclude: [
                "Resources/Info.plist", "Resources/AppIcon.svg", "Resources/AppIcon.icon",
            ],
            resources: [
                .copy("Resources/Profiles"), .copy("Resources/Products"), .copy("Resources/Licenses"),
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hant.lproj"),
            ],
            linkerSettings: [.linkedFramework("IOBluetooth"), .linkedFramework("CoreBluetooth")])
    ])
