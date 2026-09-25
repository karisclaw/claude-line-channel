import Foundation

/// Magnetic declination: the angle from **true north to magnetic north**, positive
/// east.
///
/// `true bearing = magnetic bearing + declination`
///
/// Taiwan sits at roughly −4° (about 4° west), and the value drifts year to year, so
/// it is carried with the measurement rather than baked in as a constant.
public struct MagneticDeclination: Equatable, Hashable, Sendable, Codable {

    /// Degrees east of true north. Negative means magnetic north lies to the west.
    public let degreesEast: Double

    public init(degreesEast: Double) {
        self.degreesEast = GeoAngle.signedAzimuthDifference(degreesEast, 0)
    }

    /// Derives the declination from a pair of headings for the same direction — the
    /// `trueHeading` and `magneticHeading` of one `CLHeading`.
    ///
    /// Using the device's own pair, rather than a table or a stored constant, keeps
    /// the declination consistent with whatever model the phone applied when it
    /// produced the true-north attitude.
    public init(trueHeading: Double, magneticHeading: Double) {
        self.init(degreesEast: GeoAngle.signedAzimuthDifference(trueHeading, magneticHeading))
    }

    public static let zero = MagneticDeclination(degreesEast: 0)
}

// Attitudes in this package are referenced to true north, because that is what
// CoreMotion's `.xTrueNorthZVertical` reference frame provides. These conversions
// exist so a record can also carry the raw magnetic reading — what a compass or an
// older field notebook would show at the same spot — without either number being
// derived twice or drifting from the other.

extension PlaneOrientation {

    /// This attitude restated against **magnetic** north.
    public func inMagneticNorthFrame(declination: MagneticDeclination) -> PlaneOrientation {
        PlaneOrientation(dip: dip, dipDirection: dipDirection - declination.degreesEast)
    }

    /// An attitude **recorded** against magnetic north, restated against true north.
    public func inTrueNorthFrame(declination: MagneticDeclination) -> PlaneOrientation {
        PlaneOrientation(dip: dip, dipDirection: dipDirection + declination.degreesEast)
    }
}

extension LineOrientation {

    /// This attitude restated against **magnetic** north.
    public func inMagneticNorthFrame(declination: MagneticDeclination) -> LineOrientation {
        LineOrientation(trend: trend - declination.degreesEast, plunge: plunge)
    }

    /// An attitude **recorded** against magnetic north, restated against true north.
    public func inTrueNorthFrame(declination: MagneticDeclination) -> LineOrientation {
        LineOrientation(trend: trend + declination.degreesEast, plunge: plunge)
    }
}
