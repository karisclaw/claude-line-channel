import Foundation
import OrientationCore

/// An outcrop or station: one place where measurements were taken.
public struct StationRecord: Identifiable, Equatable, Sendable, Codable {

    public var id: UUID
    /// What the geologist calls it in the notebook — "ST-03", "北側路堑".
    public var name: String
    public var createdAt: Date
    public var location: MeasurementLocation?

    /// Lithology, in whatever words the project uses.
    public var lithology: String?
    /// The sampling setup in use here, copied onto each measurement as it is taken.
    public var defaultSurveyGeometry: SurveyGeometry?
    /// Attitude of the outcrop face as a whole, where that means something.
    public var outcropFace: PlaneOrientation?
    public var notes: String?
    public var photos: [PhotoReference]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        location: MeasurementLocation? = nil,
        lithology: String? = nil,
        defaultSurveyGeometry: SurveyGeometry? = nil,
        outcropFace: PlaneOrientation? = nil,
        notes: String? = nil,
        photos: [PhotoReference] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.location = location
        self.lithology = lithology
        self.defaultSurveyGeometry = defaultSurveyGeometry
        self.outcropFace = outcropFace
        self.notes = notes
        self.photos = photos
    }
}

/// A project: the top of the hierarchy, and the unit that gets exported and shared.
public struct ProjectRecord: Identifiable, Equatable, Sendable, Codable {

    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var client: String?
    public var notes: String?

    /// Declination to apply when the device cannot supply one — an offline fallback,
    /// since a project may be opened with no network and no fresh model.
    public var fallbackDeclination: MagneticDeclination?

    /// The carry-forward behaviour the geologist prefers on this project.
    public var carryForwardPolicy: CarryForwardPolicy

    /// Convention version the project's records are written under.
    public var conventionVersion: Int

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        client: String? = nil,
        notes: String? = nil,
        fallbackDeclination: MagneticDeclination? = nil,
        carryForwardPolicy: CarryForwardPolicy = .standard,
        conventionVersion: Int = AttitudeConvention.version
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.client = client
        self.notes = notes
        self.fallbackDeclination = fallbackDeclination
        self.carryForwardPolicy = carryForwardPolicy
        self.conventionVersion = conventionVersion
    }
}
