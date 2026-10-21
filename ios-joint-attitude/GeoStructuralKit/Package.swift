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
        .library(name: "FieldRecordStore", targets: ["FieldRecordStore"]),
        .library(name: "FieldSession", targets: ["FieldSession"]),
        .library(name: "FieldUI", targets: ["FieldUI"]),
        .library(name: "FabricAnalysis", targets: ["FabricAnalysis"])
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
        ),

        // B2: the recording flow — what a trigger means in each state, what may be
        // confirmed without looking, how a finished burst becomes a record. All of it
        // Foundation-only and driven by injected events, because the screen it belongs
        // to cannot be tested here at all.
        .target(
            name: "FieldSession",
            dependencies: ["FieldRecord", "OrientationCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FieldSessionTests",
            dependencies: ["FieldSession", "FieldRecord", "OrientationCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // C: joint-set analysis — projection, density, grouping, per-set statistics.
        // Foundation only; the plots read from it rather than computing anything.
        .target(
            name: "FabricAnalysis",
            dependencies: ["OrientationCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FabricAnalysisTests",
            dependencies: ["FabricAnalysis", "OrientationCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // B2: the screens. Behind `#if canImport(SwiftUI)`, and deliberately thin —
        // every decision it could get wrong lives in FieldSession instead.
        .target(
            name: "FieldUI",
            dependencies: ["FieldSession", "FieldRecord", "OrientationCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
