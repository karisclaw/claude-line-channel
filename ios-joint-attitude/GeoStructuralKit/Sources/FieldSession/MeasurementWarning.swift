import Foundation
import OrientationCore
import FieldRecord

/// Something about a finished measurement worth the geologist's attention.
public enum MeasurementWarning: Equatable, Sendable {

    /// The magnetometer was disturbed. Costs the azimuth, not the dip.
    case magneticDisturbance(MagneticAssessment)

    /// The contact impulse pointed at a different device axis than the one selected.
    case placementDisagreement(selected: DeviceAxisPair, implied: DeviceAxisPair)

    /// The burst scattered more than the policy allows.
    case excessiveScatter(degrees: Double, limit: Double)

    /// The motion stream fell short of the requested rate. The average is still valid.
    case sampleRateShortfall(effective: Double, requested: Double)

    /// No usable position fix, so the record cannot be placed on a map or in a KML.
    case positionUnavailable

    /// The description disagrees with itself or with the type of discontinuity.
    case descriptionInconsistency(DescriptionInconsistency)
}

/// When a measurement may be accepted without looking at the screen.
///
/// ## What a warning does and does not do
///
/// A warning **never prevents saving**. The geologist is standing at the outcrop and
/// this code is not: if they look at a disturbed azimuth and decide to keep it, that is
/// their call, and an app that refused would just get the measurement written on paper
/// instead.
///
/// What a warning does is withdraw the *blind* path. With a Bluetooth key in a gloved
/// hand the screen may never be looked at, so the second press has to be safe by
/// default — and it is only safe when there is nothing to see. A flagged measurement
/// still saves, with one deliberate look.
public struct ReviewPolicy: Equatable, Sendable, Codable {

    /// Burst scatter above which a look is required, in degrees.
    ///
    /// 2° is a starting point, not a measured threshold: a steady phone on a smooth face
    /// runs well under 1°, and a rough face can scatter several degrees for honest
    /// reasons. Needs a session against real rock.
    public var maximumAngularStandardDeviation: Double

    public var lookAtMagneticDisturbance: Bool
    public var lookAtPlacementDisagreement: Bool
    public var lookAtScatter: Bool

    /// Off by default: a short stream still averages correctly, it just averaged fewer
    /// samples, and stopping the geologist for it would cost more than it saves.
    public var lookAtSampleRateShortfall: Bool

    /// Off by default: the attitude is valid without a fix, and in a gorge there may
    /// never be one.
    public var lookAtMissingPosition: Bool

    public var lookAtDescriptionInconsistency: Bool

    /// Save a clean measurement the moment the burst finishes, with no review step.
    ///
    /// Off by default. It is the fastest possible loop — hold the phone to the rock and
    /// the record appears — and it is also the one setting that can fill a project with
    /// measurements nobody ever looked at.
    public var autoConfirmWhenClean: Bool

    public init(
        maximumAngularStandardDeviation: Double = 2,
        lookAtMagneticDisturbance: Bool = true,
        lookAtPlacementDisagreement: Bool = true,
        lookAtScatter: Bool = true,
        lookAtSampleRateShortfall: Bool = false,
        lookAtMissingPosition: Bool = false,
        lookAtDescriptionInconsistency: Bool = true,
        autoConfirmWhenClean: Bool = false
    ) {
        self.maximumAngularStandardDeviation = max(maximumAngularStandardDeviation, 0)
        self.lookAtMagneticDisturbance = lookAtMagneticDisturbance
        self.lookAtPlacementDisagreement = lookAtPlacementDisagreement
        self.lookAtScatter = lookAtScatter
        self.lookAtSampleRateShortfall = lookAtSampleRateShortfall
        self.lookAtMissingPosition = lookAtMissingPosition
        self.lookAtDescriptionInconsistency = lookAtDescriptionInconsistency
        self.autoConfirmWhenClean = autoConfirmWhenClean
    }

    public static let standard = ReviewPolicy()

    /// Nothing withdraws the blind path. For a geologist who has decided to review
    /// everything later at the desk.
    public static let unattended = ReviewPolicy(
        lookAtMagneticDisturbance: false,
        lookAtPlacementDisagreement: false,
        lookAtScatter: false,
        lookAtDescriptionInconsistency: false,
        autoConfirmWhenClean: true
    )

    /// Whether this warning withdraws the blind confirmation path.
    public func requiresALook(at warning: MeasurementWarning) -> Bool {
        switch warning {
        case .magneticDisturbance: lookAtMagneticDisturbance
        case .placementDisagreement: lookAtPlacementDisagreement
        case .excessiveScatter: lookAtScatter
        case .sampleRateShortfall: lookAtSampleRateShortfall
        case .positionUnavailable: lookAtMissingPosition
        case .descriptionInconsistency: lookAtDescriptionInconsistency
        }
    }
}
