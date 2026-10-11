#if canImport(SwiftData)
import Foundation
import SwiftData
import OrientationCore
import FieldRecord

// SwiftData persistence for the field record.
//
// The whole file is behind `canImport(SwiftData)` so the package still builds where
// SwiftData does not exist — on Linux CI the target compiles to nothing rather than
// failing, which keeps `swift test` available for the parts that can be tested without
// a device.
//
// ## Why each model holds one blob plus a few loose columns
//
// Every model stores its value type — `ProjectRecord`, `StationRecord`,
// `MeasurementRecord` — as a single Codable attribute, and that attribute is the only
// source of truth. A handful of fields are then *copied* alongside it as plain columns,
// purely so `#Predicate` and sort descriptors have something to work on, since a
// predicate cannot reach inside an encoded blob.
//
// The alternative — one column per field — spreads a thirty-field record across thirty
// declarations that have to be kept in step with the value type by hand, and the failure
// mode is a field silently not being saved. Here the round trip is lossless by
// construction, and the duplicated columns are set in exactly one place: `apply(_:)`.
// Nothing else may write them.

/// A project: the unit that gets exported and shared.
@Model
public final class StoredProject {

    @Attribute(.unique) public var id: UUID

    /// The project itself. Source of truth.
    public var record: ProjectRecord

    // Derived columns — written only by `apply(_:)`.
    public var name: String
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StoredStation.project)
    public var stations: [StoredStation] = []

    public init(record: ProjectRecord) {
        self.id = record.id
        self.record = record
        self.name = record.name
        self.createdAt = record.createdAt
    }

    /// Replaces the record and refreshes the derived columns together.
    public func apply(_ record: ProjectRecord) {
        self.record = record
        self.id = record.id
        self.name = record.name
        self.createdAt = record.createdAt
    }
}

/// An outcrop or station.
@Model
public final class StoredStation {

    @Attribute(.unique) public var id: UUID

    public var record: StationRecord

    // Derived columns.
    public var name: String
    public var createdAt: Date
    public var latitude: Double?
    public var longitude: Double?

    public var project: StoredProject?

    @Relationship(deleteRule: .cascade, inverse: \StoredMeasurement.station)
    public var measurements: [StoredMeasurement] = []

    public init(record: StationRecord, project: StoredProject? = nil) {
        self.id = record.id
        self.record = record
        self.name = record.name
        self.createdAt = record.createdAt
        self.latitude = record.location?.latitude
        self.longitude = record.location?.longitude
        self.project = project
    }

    public func apply(_ record: StationRecord) {
        self.record = record
        self.id = record.id
        self.name = record.name
        self.createdAt = record.createdAt
        self.latitude = record.location?.latitude
        self.longitude = record.location?.longitude
    }
}

/// One measurement.
@Model
public final class StoredMeasurement {

    @Attribute(.unique) public var id: UUID

    public var record: MeasurementRecord

    // Derived columns: what the app filters, sorts and groups by.
    public var timestamp: Date
    public var dip: Double?
    public var dipDirection: Double?
    public var discontinuityTypeRaw: String
    public var modeRaw: String
    public var jointSetID: UUID?
    public var observer: String?

    public var station: StoredStation?

    public init(record: MeasurementRecord, station: StoredStation? = nil) {
        self.id = record.id
        self.record = record
        self.timestamp = record.timestamp
        self.dip = record.plane?.dip
        self.dipDirection = record.plane?.dipDirection
        self.discontinuityTypeRaw = record.discontinuityType.rawValue
        self.modeRaw = record.mode.rawValue
        self.jointSetID = record.jointSetID
        self.observer = record.observer
        self.station = station
    }

    public func apply(_ record: MeasurementRecord) {
        self.record = record
        self.id = record.id
        self.timestamp = record.timestamp
        self.dip = record.plane?.dip
        self.dipDirection = record.plane?.dipDirection
        self.discontinuityTypeRaw = record.discontinuityType.rawValue
        self.modeRaw = record.mode.rawValue
        self.jointSetID = record.jointSetID
        self.observer = record.observer
    }

    public var discontinuityType: DiscontinuityType? {
        DiscontinuityType(rawValue: discontinuityTypeRaw)
    }

    public var mode: MeasurementMode? {
        MeasurementMode(rawValue: modeRaw)
    }
}

// MARK: - Schema

public enum FieldRecordSchema {

    /// The models in the store, for `ModelContainer(for:)`.
    public static let models: [any PersistentModel.Type] = [
        StoredProject.self,
        StoredStation.self,
        StoredMeasurement.self
    ]

    /// Bump when a derived column is added or removed, or when the stored value types
    /// change shape.
    ///
    /// Because each model keeps one Codable blob, most changes to a record are additive
    /// and need no migration at all: a new optional field decodes as `nil` from an old
    /// blob. What *does* need a migration is a change to the derived columns, or a field
    /// whose meaning changes — and
    /// ``OrientationCore/AttitudeConvention/version`` on each record is what makes the
    /// second kind detectable rather than silent.
    public static let version = 1
}

// MARK: - Offline project creation

extension StoredProject {

    /// Creates a project with one station, all offline — the specification's "create a
    /// project with no network" requirement, which falls out of SwiftData being local.
    public static func create(
        named name: String,
        firstStation stationName: String,
        at date: Date,
        in context: ModelContext
    ) -> (project: StoredProject, station: StoredStation) {
        let project = StoredProject(record: ProjectRecord(name: name, createdAt: date))
        let station = StoredStation(
            record: StationRecord(name: stationName, createdAt: date),
            project: project
        )
        context.insert(project)
        context.insert(station)
        return (project, station)
    }
}

#endif
