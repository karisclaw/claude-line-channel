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

/// How the phone is held against a planar surface, named after the field action
/// rather than after a device axis.
///
/// The geologist picks one before measuring, and it is stored with the measurement:
/// the same device attitude yields three different planes depending on which face of
/// the phone was against the rock, and nothing in the recorded numbers reveals which
/// was used.
public enum DevicePlacement: String, CaseIterable, Sendable, Codable {
    /// Back of the phone flat on the face, screen looking away from the rock.
    case backOnFace
    /// Left side of the phone flat on the face, used the way a compass edge is.
    case leftSideOnFace
    /// Right side of the phone flat on the face.
    case rightSideOnFace
    /// Bottom (short) edge of the phone flat on the face.
    case bottomEdgeOnFace
    /// Top (short) edge of the phone flat on the face.
    case topEdgeOnFace
    /// Screen flat on the face. It works, but it means reading the rock through the
    /// side of the phone you cannot see, so it is not offered in the field picker.
    case screenOnFace

    /// The device axis pointing **out of the rock**, away from the contact surface.
    ///
    /// The outward normal points from the rock into the air — toward whoever is
    /// holding the phone — so it is the *opposite* of the axis the contacting face
    /// looks along. The phone's back looks along `-z`, so resting it on a bedding
    /// plane makes the outward normal `+z`; its left side looks along `-x`, so
    /// standing the phone on that side makes the outward normal `+x`.
    ///
    /// Both signs of an axis give the same ``PlaneOrientation``, because a plane's
    /// attitude is axial. The sign matters for the measured outward direction, which
    /// is the only record of which face of a vertical joint was touched.
    public var outwardNormalAxis: DeviceAxis {
        switch self {
        case .backOnFace: .plusZ
        case .screenOnFace: .minusZ
        case .leftSideOnFace: .plusX
        case .rightSideOnFace: .minusX
        case .bottomEdgeOnFace: .plusY
        case .topEdgeOnFace: .minusY
        }
    }

    /// The axis the contact normal lies along, ignoring which way round the phone is.
    ///
    /// Only three distinct choices affect an attitude — `x`, `y` or `z` — because the
    /// two placements on a given axis are the two faces of one plane. Anything trying
    /// to detect the placement automatically only has to pick among these three.
    public var contactAxisPair: DeviceAxisPair {
        switch self {
        case .backOnFace, .screenOnFace: .z
        case .leftSideOnFace, .rightSideOnFace: .x
        case .bottomEdgeOnFace, .topEdgeOnFace: .y
        }
    }

    /// The placements offered in the field picker, in the order to show them.
    ///
    /// ``screenOnFace`` is left out: it is geometrically valid but means working
    /// blind, and an accidental selection would produce a plausible-looking attitude
    /// 180° from the face actually touched.
    public static let fieldSelectable: [DevicePlacement] = [
        .backOnFace, .leftSideOnFace, .rightSideOnFace, .bottomEdgeOnFace, .topEdgeOnFace
    ]
}

/// An unsigned device axis — the pair of opposite directions along one axis.
public enum DeviceAxisPair: String, CaseIterable, Sendable, Codable {
    case x, y, z

    public var positiveDirection: DeviceAxis {
        switch self {
        case .x: .plusX
        case .y: .plusY
        case .z: .plusZ
        }
    }
}

/// Which edge of the phone is laid along a linear structure.
public enum DeviceEdge: String, CaseIterable, Sendable, Codable {
    case leftEdge
    case rightEdge
    case topEdge
    case bottomEdge

    /// The edges offered in the field picker, in the order to show them.
    public static let fieldSelectable: [DeviceEdge] = [.leftEdge, .rightEdge, .bottomEdge, .topEdge]

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
