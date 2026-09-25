import Foundation

/// A device axis, expressed in Apple's device frame (phone upright, facing you:
/// `+x` right, `+y` top, `+z` out of the screen).
public enum DeviceAxis: String, CaseIterable, Sendable, Codable {
    case plusX, minusX, plusY, minusY, plusZ, minusZ

    public var vector: Vector3 {
        switch self {
        case .plusX: Vector3(1, 0, 0)
        case .minusX: Vector3(-1, 0, 0)
        case .plusY: Vector3(0, 1, 0)
        case .minusY: Vector3(0, -1, 0)
        case .plusZ: Vector3(0, 0, 1)
        case .minusZ: Vector3(0, 0, -1)
        }
    }

    public var opposite: DeviceAxis {
        switch self {
        case .plusX: .minusX
        case .minusX: .plusX
        case .plusY: .minusY
        case .minusY: .plusY
        case .plusZ: .minusZ
        case .minusZ: .plusZ
        }
    }
}

/// Converts a device attitude quaternion into a geological attitude.
///
/// The app layer obtains the quaternion from
/// `CMMotionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical)` — which
/// requires CoreLocation to be running, otherwise the true-north reference (and
/// therefore the magnetic declination correction) is unavailable — and passes it
/// here. Nothing in this file imports CoreMotion, so all of it is testable with
/// synthesized quaternions.
public enum DeviceAttitude {

    /// The default axis for the contact (flat-on-rock) method.
    ///
    /// With the back of the phone flat against the rock face, the screen looks away
    /// from the rock, so the device `+z` axis is the outward normal of the face.
    public static let defaultContactAxis: DeviceAxis = .plusZ

    /// The default axis for aligning the phone with a linear structure.
    ///
    /// The bottom edge of the phone is pointed along the lineation, so the device
    /// `-y` axis lies along the line. Because a lineation is axial, pointing the
    /// top edge along it instead gives the same answer.
    public static let defaultLineationAxis: DeviceAxis = .minusY

    /// Plane attitude from a device attitude quaternion.
    ///
    /// - Parameters:
    ///   - attitude: device-to-world rotation, world frame NWU / true north.
    ///   - contactAxis: the device axis held normal to the rock face.
    /// - Returns: the plane attitude, or `nil` if the quaternion is degenerate.
    public static func plane(
        from attitude: Quaternion,
        contactAxis: DeviceAxis = defaultContactAxis
    ) -> PlaneOrientation? {
        // The quaternion is validated rather than leaned on: `rotate` falls back to
        // the identity rotation for a degenerate one, which would report a dropped
        // sensor sample as a perfectly horizontal joint.
        guard let attitude = attitude.normalized else { return nil }
        return PlaneOrientation(measuredNormal: attitude.rotate(contactAxis.vector))
    }

    /// Lineation attitude from a device attitude quaternion.
    ///
    /// - Parameters:
    ///   - attitude: device-to-world rotation, world frame NWU / true north.
    ///   - alignmentAxis: the device axis laid along the linear structure.
    /// - Returns: the line attitude, or `nil` if the quaternion is degenerate.
    public static func line(
        from attitude: Quaternion,
        alignmentAxis: DeviceAxis = defaultLineationAxis
    ) -> LineOrientation? {
        guard let attitude = attitude.normalized else { return nil }
        return LineOrientation(measuredAxis: attitude.rotate(alignmentAxis.vector))
    }

    /// World-frame direction of a device axis, for callers that need the raw vector
    /// (sample averaging, stillness checks, calibration screens).
    ///
    /// Returns `nil` for a degenerate quaternion, for the same reason as above.
    public static func worldVector(of axis: DeviceAxis, for attitude: Quaternion) -> Vector3? {
        guard let attitude = attitude.normalized else { return nil }
        return attitude.rotate(axis.vector)
    }
}
