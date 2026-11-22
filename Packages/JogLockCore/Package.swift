// swift-tools-version: 6.0
//
// The parts of Jog Lock that don't need an iPhone: the distance engine, run
// logs and run files. Kept in a package so `swift test` can run them on any
// Mac or Linux machine, including CI.

import PackageDescription

let package = Package(
    name: "JogLockCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JogLockCore", targets: ["JogLockCore"]),
    ],
    targets: [
        .target(name: "JogLockCore"),
        .testTarget(name: "JogLockCoreTests", dependencies: ["JogLockCore"]),
    ]
)
