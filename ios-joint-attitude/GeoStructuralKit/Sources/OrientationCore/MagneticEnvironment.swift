import Foundation

/// Mirrors `CMMagneticFieldCalibrationAccuracy`, raw values included, so a reading can
/// be carried through this package and stored without a lookup table in between.
public enum MagneticFieldAccuracy: Int, CaseIterable, Sendable, Codable {
    case uncalibrated = -1
    case low = 0
    case medium = 1
    case high = 2
}

/// What the magnetometer and the heading looked like at the moment of a measurement.
///
/// Recorded with every measurement. Rock containing magnetite, basic igneous rock, and
/// anything near a steel guardrail or rebar will bend the field, and the only way to
/// know afterwards that a dip direction is suspect is if the reading was kept.
public struct MagneticEnvironment: Equatable, Sendable, Codable {

    /// Magnitude of `CMMagneticField`, in µT. `nil` if the app had no reading.
    public var fieldStrength: Double?

    public var accuracy: MagneticFieldAccuracy

    /// `CLHeading.headingAccuracy`, in degrees. Negative means the heading is invalid,
    /// which is what CoreLocation uses to say so.
    public var headingAccuracy: Double?

    public init(
        fieldStrength: Double? = nil,
        accuracy: MagneticFieldAccuracy = .uncalibrated,
        headingAccuracy: Double? = nil
    ) {
        self.fieldStrength = fieldStrength
        self.accuracy = accuracy
        self.headingAccuracy = headingAccuracy
    }
}

/// Thresholds for judging the magnetic environment.
public struct MagneticCriteria: Equatable, Sendable {

    /// Undisturbed field strength at the Earth's surface, in µT. Outside this,
    /// something local is adding to the field.
    public var earthFieldRange: ClosedRange<Double>

    /// Heading accuracy above which the azimuth is only marginal, in degrees.
    public var marginalHeadingAccuracy: Double

    /// Heading accuracy above which the azimuth should not be trusted, in degrees.
    public var unusableHeadingAccuracy: Double

    public init(
        earthFieldRange: ClosedRange<Double> = 25...65,
        marginalHeadingAccuracy: Double = 10,
        unusableHeadingAccuracy: Double = 20
    ) {
        self.earthFieldRange = earthFieldRange
        self.marginalHeadingAccuracy = marginalHeadingAccuracy
        self.unusableHeadingAccuracy = unusableHeadingAccuracy
    }
}

/// The verdict on a magnetic environment, with the reasons behind it.
public struct MagneticAssessment: Equatable, Sendable, Codable {

    public enum Verdict: String, Sendable, Codable {
        case good
        case marginal
        case disturbed

        /// Higher is worse, for combining several readings.
        public var severity: Int {
            switch self {
            case .good: 0
            case .marginal: 1
            case .disturbed: 2
            }
        }
    }

    public enum Reason: String, Sendable, Codable {
        /// Field strength outside the undisturbed range: magnetite, basic rock, rebar,
        /// a steel guardrail, a vehicle.
        case fieldStrengthOutsideEarthRange
        case fieldStrengthUnknown
        case magnetometerUncalibrated
        case magnetometerPoorlyCalibrated
        case headingInvalid
        case headingAccuracyMarginal
        case headingAccuracyUnusable
    }

    public let verdict: Verdict
    public let reasons: [Reason]

    public var isDisturbed: Bool { verdict == .disturbed }

    /// A disturbed magnetic environment corrupts the **azimuth** — dip direction,
    /// strike, trend — and leaves the **dip** and **plunge** intact, because those
    /// come from gravity by way of the accelerometer, which magnetite cannot touch.
    ///
    /// Worth saying in the UI: a warning does not mean the measurement is wasted. The
    /// inclination is still good, and a dip recorded with a flagged azimuth is
    /// recoverable later from a re-measured direction.
    public var affectsAzimuthOnly: Bool { true }

    /// Applies the project's rule: a warning if the field strength is off the
    /// undisturbed range, or the magnetometer reports `.low` or `.uncalibrated`.
    /// Heading accuracy adds the softer grades.
    public static func assess(
        _ environment: MagneticEnvironment,
        criteria: MagneticCriteria = MagneticCriteria()
    ) -> MagneticAssessment {
        var reasons: [Reason] = []
        var verdict = Verdict.good

        func raise(to level: Verdict) {
            if level.severity > verdict.severity { verdict = level }
        }

        if let strength = environment.fieldStrength {
            if !criteria.earthFieldRange.contains(strength) {
                reasons.append(.fieldStrengthOutsideEarthRange)
                raise(to: .disturbed)
            }
        } else {
            reasons.append(.fieldStrengthUnknown)
            raise(to: .marginal)
        }

        switch environment.accuracy {
        case .uncalibrated:
            reasons.append(.magnetometerUncalibrated)
            raise(to: .disturbed)
        case .low:
            reasons.append(.magnetometerPoorlyCalibrated)
            raise(to: .disturbed)
        case .medium, .high:
            break
        }

        if let accuracy = environment.headingAccuracy {
            if accuracy < 0 {
                reasons.append(.headingInvalid)
                raise(to: .disturbed)
            } else if accuracy > criteria.unusableHeadingAccuracy {
                reasons.append(.headingAccuracyUnusable)
                raise(to: .disturbed)
            } else if accuracy > criteria.marginalHeadingAccuracy {
                reasons.append(.headingAccuracyMarginal)
                raise(to: .marginal)
            }
        }

        return MagneticAssessment(verdict: verdict, reasons: reasons)
    }
}
