import Foundation
import OrientationCore

/// One measurement, as plain values.
///
/// This is the shape the SwiftData model stores, the exporters read, and the tests
/// exercise. Keeping it a value type means the geology can be tested without a database
/// and without a device.
public struct MeasurementRecord: Identifiable, Equatable, Sendable, Codable {

    // MARK: Identity

    public var id: UUID
    public var timestamp: Date
    public var mode: MeasurementMode

    /// Which convention set the attitude is expressed in. See
    /// ``OrientationCore/AttitudeConvention``.
    ///
    /// Stamped on every record because nothing in a dip/dip-direction pair reveals the
    /// convention that produced it — 45/090 and 45/270 are both valid attitudes.
    public var conventionVersion: Int

    // MARK: Attitude

    /// The planar attitude, for a planar measurement.
    public var plane: PlaneOrientation?

    /// The linear attitude, for a lineation.
    public var lineation: LineOrientation?

    /// Scatter of the sampling burst, in degrees. `nil` for a manual entry.
    public var angularStandardDeviation: Double?

    /// Samples averaged. `nil` for a manual entry.
    public var sampleCount: Int?

    /// Azimuth of the rock face's outward normal as measured, `0..<360`.
    ///
    /// The one piece of information a dip/dip-direction pair cannot hold: which face of
    /// a vertical joint the phone was held against. For a dipping plane it is redundant
    /// with the dip direction; for a vertical one it is the only record, and a vertical
    /// joint's facing direction is what a slope-stability reader wants.
    public var measuredFaceAzimuth: Double?

    // MARK: How it was taken

    /// Which face of the phone was against the rock, and which edge along the structure.
    public var geometry: MeasurementGeometry

    /// The magnetometer and heading at the moment of measurement.
    public var magneticEnvironment: MagneticEnvironment?

    /// Declination in force, so the magnetic-north reading can be reconstructed.
    public var declination: MagneticDeclination?

    /// Fit quality, for a LiDAR measurement.
    public var fitQuality: PlaneFitQuality?

    /// The scanline or window this discontinuity was sampled from.
    ///
    /// Held on the measurement, not only on the station, so an exported row is
    /// self-describing and a station with two scanlines does not need two stations. The
    /// UI copies it forward from the previous measurement, so it is typed once.
    public var surveyGeometry: SurveyGeometry?

    // MARK: Where

    public var location: MeasurementLocation?

    // MARK: Geology

    public var discontinuityType: DiscontinuityType
    public var isrm: DiscontinuityDescription

    // MARK: Bookkeeping

    /// Written back by the set analysis in the clustering module. `nil` until then.
    public var jointSetID: UUID?
    public var setAssignedAt: Date?

    public var observer: String?
    public var notes: String?
    public var photos: [PhotoReference]
    public var voiceMemo: VoiceMemoReference?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        mode: MeasurementMode,
        conventionVersion: Int = AttitudeConvention.version,
        plane: PlaneOrientation? = nil,
        lineation: LineOrientation? = nil,
        angularStandardDeviation: Double? = nil,
        sampleCount: Int? = nil,
        measuredFaceAzimuth: Double? = nil,
        geometry: MeasurementGeometry = .default,
        magneticEnvironment: MagneticEnvironment? = nil,
        declination: MagneticDeclination? = nil,
        fitQuality: PlaneFitQuality? = nil,
        surveyGeometry: SurveyGeometry? = nil,
        location: MeasurementLocation? = nil,
        discontinuityType: DiscontinuityType = .joint,
        isrm: DiscontinuityDescription = .empty,
        jointSetID: UUID? = nil,
        setAssignedAt: Date? = nil,
        observer: String? = nil,
        notes: String? = nil,
        photos: [PhotoReference] = [],
        voiceMemo: VoiceMemoReference? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.conventionVersion = conventionVersion
        self.plane = plane
        self.lineation = lineation
        self.angularStandardDeviation = angularStandardDeviation
        self.sampleCount = sampleCount
        self.measuredFaceAzimuth = measuredFaceAzimuth
        self.geometry = geometry
        self.magneticEnvironment = magneticEnvironment
        self.declination = declination
        self.fitQuality = fitQuality
        self.surveyGeometry = surveyGeometry
        self.location = location
        self.discontinuityType = discontinuityType
        self.isrm = isrm
        self.jointSetID = jointSetID
        self.setAssignedAt = setAssignedAt
        self.observer = observer
        self.notes = notes
        self.photos = photos
        self.voiceMemo = voiceMemo
    }

    // MARK: Derived

    /// Right-hand-rule strike, derived rather than stored — a stored copy is one more
    /// thing that can disagree with the dip direction after an edit.
    public var strike: Double? { plane?.strike }

    /// The magnetic-north attitude the same measurement would have had, for comparison
    /// with a compass reading or an older notebook.
    public var planeInMagneticNorthFrame: PlaneOrientation? {
        guard let plane, let declination else { return nil }
        return plane.inMagneticNorthFrame(declination: declination)
    }

    /// The magnetic assessment, if there was a reading to assess.
    public var magneticAssessment: MagneticAssessment? {
        magneticEnvironment.map { MagneticAssessment.assess($0) }
    }

    /// `true` when the azimuth of this record should be treated as suspect.
    ///
    /// The dip is not: it comes from gravity, which magnetic disturbance does not touch.
    public var hasSuspectAzimuth: Bool {
        magneticAssessment?.isDisturbed ?? false
    }

    /// `true` when the record carries an attitude at all.
    public var hasAttitude: Bool { plane != nil || lineation != nil }
}
