// swift-tools-version: 6.0
import PackageDescription

// GeoStructuralKit — pure-computation core for the field joint-attitude app.
//
// This package has NO dependency on UIKit/SwiftUI, CoreMotion, CoreLocation or
// ARKit. It only consumes plain numbers (quaternions, vectors, angles), so every
// function here is unit-testable on any platform, including Linux CI.
//
// The app layer is responsible for talking to the sensors and handing the
// resulting quaternion / point cloud to this package.

let package = Package(
    name: "GeoStructuralKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OrientationCore", targets: ["OrientationCore"]),
        .library(name: "FieldRecord", targets: ["FieldRecord"]),
        .library(name: "FieldRecordStore", targets: ["FieldRecordStore"])
    ],
    targets: [
        // A1 + A2: attitude conversion, sampling, quality. Foundation only.
        .target(
            name: "OrientationCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OrientationCoreTests",
            dependencies: ["OrientationCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // B: the field record as plain values — the geology, the ISRM descriptors, the
        // survey geometry. Foundation only, so it runs in CI without Xcode.
        .target(
            name: "FieldRecord",
            dependencies: ["OrientationCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FieldRecordTests",
            dependencies: ["FieldRecord", "OrientationCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // B: SwiftData persistence. Everything in it is behind `#if canImport(SwiftData)`
        // so the package still builds where SwiftData does not exist; the target is then
        // empty rather than broken.
        .target(
            name: "FieldRecordStore",
            dependencies: ["FieldRecord"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
