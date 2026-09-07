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
        .library(name: "OrientationCore", targets: ["OrientationCore"])
    ],
    targets: [
        .target(
            name: "OrientationCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OrientationCoreTests",
            dependencies: ["OrientationCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
