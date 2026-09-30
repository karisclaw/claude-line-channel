import Foundation

/// The error in a calibration check, split by where it came from.
///
/// The split is the useful part. Tilt comes from the accelerometer and is almost always
/// good; azimuth comes from the magnetometer and is what goes wrong in the field. A
/// check that reports 12° of total error is not actionable; one that reports 0.3° of
/// tilt error and 12° of azimuth error says "the magnetometer needs recalibrating, or
/// you are standing next to something steel".
public struct CalibrationResult: Equatable, Sendable {

    public let reference: PlaneOrientation
    public let measured: PlaneOrientation

    /// Inclination error, in degrees. Gravity-referenced.
    public let tiltError: Double

    /// Azimuth error, signed, in degrees. Magnetometer-referenced.
    /// `nil` when the reference has no azimuth to compare against — a horizontal
    /// surface, or a vertical one whose facing direction was not given.
    public let azimuthError: Double?

    /// The actual angle between the two planes, in degrees.
    public let totalError: Double

    /// Whether both components are within `tolerance` degrees.
    public func isWithin(_ tolerance: Double) -> Bool {
        tiltError <= tolerance && abs(azimuthError ?? 0) <= tolerance
    }
}

/// Calibration checks against surfaces whose attitude is already known.
public enum CalibrationCheck {

    /// Phone flat on a surface known to be horizontal — a bench, a spirit-levelled
    /// plate. Only the tilt can be checked: a horizontal plane has no azimuth.
    public static func againstHorizontal(_ measured: PlaneOrientation) -> CalibrationResult {
        let reference = PlaneOrientation(dip: 0, dipDirection: 0)
        return CalibrationResult(
            reference: reference,
            measured: measured,
            tiltError: measured.dip,
            azimuthError: nil,
            totalError: measured.dip
        )
    }

    /// Phone against a surface known to be vertical — a plumb line, a door frame.
    ///
    /// Pass `facing` when the direction the surface looks toward is known (a wall on a
    /// surveyed bearing), and the azimuth is checked too. Without it only the tilt is,
    /// and the total error is the deviation from vertical.
    public static func againstVertical(
        _ measured: PlaneOrientation,
        facing expectedDipDirection: Double? = nil
    ) -> CalibrationResult {
        guard let expected = expectedDipDirection else {
            let reference = PlaneOrientation(dip: 90, dipDirection: measured.dipDirection)
            let tilt = abs(90 - measured.dip)
            return CalibrationResult(
                reference: reference,
                measured: measured,
                tiltError: tilt,
                azimuthError: nil,
                totalError: tilt
            )
        }
        return against(PlaneOrientation(dip: 90, dipDirection: expected), measured: measured)
    }

    /// Check against any reference plane whose attitude is known.
    public static func against(
        _ reference: PlaneOrientation,
        measured: PlaneOrientation
    ) -> CalibrationResult {
        CalibrationResult(
            reference: reference,
            measured: measured,
            tiltError: abs(measured.dip - reference.dip),
            azimuthError: GeoAngle.signedAzimuthDifference(
                measured.dipDirection, reference.dipDirection
            ),
            totalError: measured.angle(to: reference)
        )
    }
}

/// Tracks how much of the orientation sphere a figure-of-eight has covered, to drive a
/// progress indicator.
///
/// Feed it the **device-frame** gravity direction (`CMDeviceMotion.gravity`), which
/// sweeps across the sphere as the phone is turned — that motion is exactly what a
/// figure-of-eight is for. Coverage is counted in octants: eight sign combinations, an
/// obvious and complete partition, with none of the guesswork a finer binning would
/// need.
///
/// This guides the user; it does not decide anything. The authority on whether the
/// magnetometer is calibrated is iOS's own ``MagneticFieldAccuracy``, which is what
/// ``MagneticAssessment`` reads. Full coverage here with the accuracy still `.low`
/// means keep going, not "done".
public struct MagnetometerCoverage: Equatable, Sendable {

    private var visited: Set<Int> = []

    public init() {}

    /// Records one orientation. Vectors too short to have a direction are ignored.
    public mutating func add(deviceFrameDirection direction: Vector3) {
        guard let unit = direction.normalized else { return }
        visited.insert(MagnetometerCoverage.octant(of: unit))
    }

    /// Octants visited so far, `0...8`.
    public var visitedOctants: Int { visited.count }

    /// Fraction of the sphere's octants visited, `0...1`.
    public var fraction: Double { Double(visited.count) / 8.0 }

    public var isComplete: Bool { visited.count == 8 }

    public mutating func reset() { visited.removeAll(keepingCapacity: true) }

    /// Index `0...7` from the signs of the three components.
    ///
    /// A component of exactly zero counts as positive. That biases a vector lying on an
    /// octant boundary toward one side, which costs nothing: the point is to detect
    /// that the phone has been turned through all eight regions, and a boundary vector
    /// belongs to both.
    static func octant(of unit: Vector3) -> Int {
        (unit.x >= 0 ? 1 : 0) | (unit.y >= 0 ? 2 : 0) | (unit.z >= 0 ? 4 : 0)
    }
}
