import Foundation

/// How a measurement was physically taken.
///
/// Stored with every measurement, because it cannot be recovered afterwards: the same
/// device attitude gives three different planes depending on which face of the phone
/// was against the rock, and the resulting dip and dip direction look equally
/// plausible in each case. A record without this is a record whose 90° errors cannot
/// be found later.
public struct MeasurementGeometry: Equatable, Hashable, Sendable, Codable {

    /// Which face of the phone was held against the rock, for a planar measurement.
    public var placement: DevicePlacement

    /// Which edge of the phone was laid along the structure, for a linear measurement.
    public var edge: DeviceEdge

    public init(
        placement: DevicePlacement = DeviceAttitude.defaultPlacement,
        edge: DeviceEdge = DeviceAttitude.defaultLineationEdge
    ) {
        self.placement = placement
        self.edge = edge
    }

    /// The setup a geologist who has not changed anything is measuring with.
    public static let `default` = MeasurementGeometry()

    /// Plane attitude from a device attitude, using this setup.
    public func plane(from attitude: Quaternion) -> PlaneOrientation? {
        DeviceAttitude.plane(from: attitude, placement: placement)
    }

    /// Lineation attitude from a device attitude, using this setup.
    public func line(from attitude: Quaternion) -> LineOrientation? {
        DeviceAttitude.line(from: attitude, edge: edge)
    }

    /// The outward normal of the rock face in world coordinates, as measured.
    ///
    /// Signed, unlike the attitude: this is what records which face of a vertical
    /// joint the phone was held against.
    public func outwardNormal(from attitude: Quaternion) -> Vector3? {
        DeviceAttitude.worldVector(of: placement.outwardNormalAxis, for: attitude)
    }
}
