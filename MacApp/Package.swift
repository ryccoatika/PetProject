// swift-tools-version: 5.9
//
//  Open this file in Xcode to get indexing, breakpoints and Instruments:
//
//      open Package.swift
//
//  It builds the binary. The .app bundle — Info.plist, icon, skins, signature
//  — is assembled by ./build.sh, which is what you run to see the pet.

import PackageDescription

let package = Package(
    name: "Pet",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "Pet",
            path: "Sources/Pet"
        )
    ]
)
