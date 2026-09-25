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

/// How the phone is held against a planar surface, named the way it is done in the
/// field rather than by device axis.
///
/// The outward normal of the rock face is whichever device axis points away from the
/// rock for that placement.
public enum DevicePlacement: String, CaseIterable, Sendable, Codable {
    /// Back of the phone flat on the face, screen looking away from the rock.
    case backOnFace
    /// Left side of the phone flat on the face, used the way a compass edge is.
    case leftSideOnFace
    case rightSideOnFace
    case bottomEdgeOnFace
    case topEdgeOnFace
    /// Screen flat on the face. Included for completeness; it means the back of the
    /// phone is what you are reading, which is rarely what anyone wants.
    case screenOnFace

    /// The device axis that points out of the rock for this placement.
    public var outwardNormalAxis: DeviceAxis {
        switch self {
        case .backOnFace: .plusZ
        case .screenOnFace: .minusZ
        case .leftSideOnFace: .minusX
        case .rightSideOnFace: .plusX
        case .bottomEdgeOnFace: .minusY
        case .topEdgeOnFace: .plusY
        }
    }
}

/// Which edge of the phone is laid along a linear structure.
public enum DeviceEdge: String, CaseIterable, Sendable, Codable {
    case leftEdge
    case rightEdge
    case topEdge
    case bottomEdge

    /// The device axis running **along** this edge.
    ///
    /// The long edges — left and right — run from the bottom of the phone to the
    /// top, so they lie along `y`. The short edges — top and bottom — run across the
    /// phone, so they lie along `x`. Left and right therefore give the same axis, as
    /// do top and bottom; the cases are kept distinct because they name different
    /// physical acts, and a lineation is axial, so which way along the edge the phone
    /// points never matters.
    public var axis: DeviceAxis {
        switch self {
        case .leftEdge, .rightEdge: .plusY
        case .topEdge, .bottomEdge: .plusX
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

    /// The default placement for the contact method: the back of the phone flat
    /// against the rock face, so the device `+z` axis is the face's outward normal.
    public static let defaultPlacement: DevicePlacement = .backOnFace

    /// The default edge to lay along a linear structure: the left edge, which runs
    /// along the device `y` axis.
    public static let defaultLineationEdge: DeviceEdge = .leftEdge

    /// The device axis corresponding to ``defaultPlacement``.
    public static var defaultContactAxis: DeviceAxis { defaultPlacement.outwardNormalAxis }

    /// The device axis corresponding to ``defaultLineationEdge``.
    public static var defaultLineationAxis: DeviceAxis { defaultLineationEdge.axis }

    /// Plane attitude from a device attitude quaternion.
    ///
    /// - Parameters:
    ///   - attitude: device-to-world rotation, world frame NWU / true north.
    ///   - contactAxis: the device axis held normal to the rock face.
    /// - Returns: the plane attitude, or `nil` if the quaternion is degenerate.
    public static func plane(
        from attitude: Quaternion,
        contactAxis: DeviceAxis = DeviceAttitude.defaultContactAxis
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
        alignmentAxis: DeviceAxis = DeviceAttitude.defaultLineationAxis
    ) -> LineOrientation? {
        guard let attitude = attitude.normalized else { return nil }
        return LineOrientation(measuredAxis: attitude.rotate(alignmentAxis.vector))
    }

    /// Plane attitude from a placement described in field terms.
    public static func plane(
        from attitude: Quaternion,
        placement: DevicePlacement
    ) -> PlaneOrientation? {
        plane(from: attitude, contactAxis: placement.outwardNormalAxis)
    }

    /// Lineation attitude from the edge laid along the structure.
    public static func line(
        from attitude: Quaternion,
        edge: DeviceEdge
    ) -> LineOrientation? {
        line(from: attitude, alignmentAxis: edge.axis)
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
