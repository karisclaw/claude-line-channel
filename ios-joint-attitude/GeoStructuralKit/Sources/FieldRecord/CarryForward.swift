import Foundation
import OrientationCore

/// What a new measurement inherits from the one before it.
///
/// The specification asks to "copy the previous settings for fast consecutive
/// measurement", and the fast path is where mistakes get recorded, so what is *not*
/// copied matters more than what is. The attitude, the identity, the timestamp, the
/// location, the photographs, the notes and the set assignment are never copied, no
/// matter what this policy says — see ``MeasurementRecord/next(after:policy:timestamp:)``.
public struct CarryForwardPolicy: Equatable, Sendable, Codable {

    /// The kind of discontinuity — usually the same down a scanline.
    public var discontinuityType: Bool
    /// The ISRM descriptive block. On by default: a joint set tends to look alike, and
    /// the geologist edits the fields that differ.
    public var isrm: Bool
    /// Who is measuring.
    public var observer: Bool
    /// The scanline or window.
    public var surveyGeometry: Bool
    /// Which face of the phone is against the rock, and which edge along a structure.
    public var deviceGeometry: Bool
    /// How the attitude is being obtained.
    public var mode: Bool

    public init(
        discontinuityType: Bool = true,
        isrm: Bool = true,
        observer: Bool = true,
        surveyGeometry: Bool = true,
        deviceGeometry: Bool = true,
        mode: Bool = true
    ) {
        self.discontinuityType = discontinuityType
        self.isrm = isrm
        self.observer = observer
        self.surveyGeometry = surveyGeometry
        self.deviceGeometry = deviceGeometry
        self.mode = mode
    }

    /// Everything that can be carried, is.
    public static let standard = CarryForwardPolicy()

    /// Nothing is carried — for when the next discontinuity has nothing in common with
    /// the last. Named `fresh` rather than `none`, which `Optional.none` would shadow.
    public static let fresh = CarryForwardPolicy(
        discontinuityType: false,
        isrm: false,
        observer: false,
        surveyGeometry: false,
        deviceGeometry: false,
        mode: false
    )

    /// The setup is kept but the description is not — for a station where every joint
    /// is described individually.
    public static let setupOnly = CarryForwardPolicy(isrm: false)
}

extension MeasurementRecord {

    /// The type a record starts as when the previous one's type is not carried forward.
    ///
    /// Named rather than written inline in two places: the recorder has to predict what
    /// a new record will inherit in order to check it, and a second literal `.joint`
    /// would be a second thing to keep in step.
    public static let defaultDiscontinuityType: DiscontinuityType = .joint

    /// A blank record that inherits the settings of `previous` according to `policy`.
    ///
    /// Six things are never inherited, whatever the policy:
    ///
    /// - the identity, so the two records cannot collide;
    /// - the attitude, because a carried-over attitude is a duplicate measurement
    ///   wearing a new timestamp, and nothing downstream could tell it from a real one;
    /// - the burst quality figures, which belong to the attitude they describe;
    /// - the position, which moves as the geologist moves along the exposure;
    /// - the photographs, voice memo and free-text notes, which are about one
    ///   discontinuity;
    /// - the joint-set assignment, which the clustering writes back and must not be
    ///   pre-filled by hand.
    public static func next(
        after previous: MeasurementRecord,
        policy: CarryForwardPolicy = .standard,
        timestamp: Date,
        id: UUID = UUID()
    ) -> MeasurementRecord {
        MeasurementRecord(
            id: id,
            timestamp: timestamp,
            mode: policy.mode ? previous.mode : .contact,
            conventionVersion: AttitudeConvention.version,
            geometry: policy.deviceGeometry ? previous.geometry : .default,
            surveyGeometry: policy.surveyGeometry ? previous.surveyGeometry : nil,
            discontinuityType: policy.discontinuityType
                ? previous.discontinuityType
                : MeasurementRecord.defaultDiscontinuityType,
            isrm: policy.isrm ? previous.isrm : .empty,
            observer: policy.observer ? previous.observer : nil
        )
    }
}
