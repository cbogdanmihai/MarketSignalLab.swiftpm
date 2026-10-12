// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "MarketSignalLab",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "MarketSignalLab",
            targets: ["AppModule"],
            bundleIdentifier: "com.marketsignallab.app",
            teamIdentifier: "",
            displayVersion: "0.8.2",
            bundleVersion: "45",
            appIcon: .placeholder(icon: .star),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .portraitUpsideDown,
                .landscapeRight,
                .landscapeLeft
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources/AppModule",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
