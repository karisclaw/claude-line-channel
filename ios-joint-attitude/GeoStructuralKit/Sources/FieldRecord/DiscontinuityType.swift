import Foundation

/// The kind of discontinuity a measurement is of.
///
/// The standard cases are the ones worth making queryable and comparable across
/// projects; `other` carries anything else as free text rather than forcing a
/// taxonomy on a site that does not fit it. The Chinese term is given for each so the
/// UI has one place to read them from.
///
/// Encoded as its ``storageKey`` — a plain string — rather than through the synthesized
/// representation for an enum with an associated value, because this value appears as a
/// database column and in exported files, where `{"joint":{}}` would be both ugly and
/// fragile.
public enum DiscontinuityType: Equatable, Hashable, Sendable {

    /// 節理 — a joint, with no visible displacement.
    case joint
    /// 席狀節理／解壓節理 — a sheeting joint, formed by unloading, typically slope-parallel.
    case sheetingJoint
    /// 層面 — a bedding plane.
    case bedding
    /// 斷層 — a discrete fault surface, with displacement.
    case fault
    /// 斷層帶 — a fault zone: a thickness of broken rock or gouge, not one surface.
    case faultZone
    /// 剪裂帶 — a shear zone, with distributed strain across a thickness.
    case shearZone
    /// 葉理 — foliation in a metamorphic rock.
    case foliation
    /// 片理 — schistosity, where it is worth distinguishing from foliation generally.
    case schistosity
    /// 劈理 — cleavage.
    case cleavage
    /// 脈 — a vein, a mineral-filled fracture.
    case vein
    /// 張裂隙 — a tension gash, usually mineral-filled and en échelon.
    case tensionGash
    /// 縫合線 — a stylolite, a dissolution seam.
    case stylolite
    /// 不整合面 — an unconformity.
    case unconformity
    /// 侵入接觸面 — an intrusive contact.
    case intrusiveContact
    /// 流面 — flow banding in a volcanic rock.
    case flowBanding
    /// Anything else, named in the field. The text is kept verbatim.
    case other(String)

    /// Every case except ``other``, in the order to offer them.
    public static let standardCases: [DiscontinuityType] = [
        .joint, .sheetingJoint, .bedding, .fault, .faultZone, .shearZone,
        .foliation, .schistosity, .cleavage, .vein, .tensionGash, .stylolite,
        .unconformity, .intrusiveContact, .flowBanding
    ]

    /// The cases a field picker should show before the "more" disclosure.
    ///
    /// Not a judgement about which rocks matter: it is a judgement about a cold hand on
    /// a small screen. Every extra row on the first screen slows down every
    /// measurement, including the ones that only ever use `joint`.
    public static let commonCases: [DiscontinuityType] = [
        .joint, .bedding, .fault, .foliation, .vein
    ]

    /// Stable key for database columns, predicates and exported files.
    ///
    /// `other` is encoded as `other:<text>`, so the label survives a round trip rather
    /// than collapsing every unusual feature into one bucket.
    public var storageKey: String {
        switch self {
        case .joint: "joint"
        case .sheetingJoint: "sheetingJoint"
        case .bedding: "bedding"
        case .fault: "fault"
        case .faultZone: "faultZone"
        case .shearZone: "shearZone"
        case .foliation: "foliation"
        case .schistosity: "schistosity"
        case .cleavage: "cleavage"
        case .vein: "vein"
        case .tensionGash: "tensionGash"
        case .stylolite: "stylolite"
        case .unconformity: "unconformity"
        case .intrusiveContact: "intrusiveContact"
        case .flowBanding: "flowBanding"
        case .other(let label): "other:\(label)"
        }
    }

    public init?(storageKey key: String) {
        if key.hasPrefix("other:") {
            self = .other(String(key.dropFirst("other:".count)))
            return
        }
        guard let match = DiscontinuityType.standardCases.first(where: { $0.storageKey == key })
        else { return nil }
        self = match
    }

    /// `true` for the types that occupy a **thickness** rather than a single surface.
    ///
    /// A fault zone or a shear zone measured as though it were one plane loses the
    /// quantity an engineer asks about first. ``DiscontinuityDescription/zoneThicknessMetres``
    /// is where that goes, and ``DiscontinuityDescription/zoneThicknessIssue(for:)``
    /// says when it is missing or when it has been filled in for something that has no
    /// thickness.
    public var isZone: Bool {
        switch self {
        case .faultZone, .shearZone: true
        default: false
        }
    }
}

extension DiscontinuityType: Codable {

    public init(from decoder: any Decoder) throws {
        let key = try decoder.singleValueContainer().decode(String.self)
        guard let value = DiscontinuityType(storageKey: key) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "unknown discontinuity type '\(key)'"
                )
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }
}

/// How an attitude was obtained.
public enum MeasurementMode: String, CaseIterable, Sendable, Codable {
    /// The back (or another face) of the phone held against the rock.
    case contact
    /// Fitted to a LiDAR point cloud, without touching the rock.
    case lidar
    /// Typed in — from a compass-clinometer, or from an older notebook.
    case manual
}

/// Where a measurement was taken.
///
/// Mirrors `CLLocation`, including the trap that **a negative accuracy means invalid**,
/// not excellent. `CLLocation` reports `-1` for `horizontalAccuracy` when it has no
/// fix, and a reading sorted or filtered as though smaller were better puts the worst
/// data first.
public struct MeasurementLocation: Equatable, Sendable, Codable {

    public var latitude: Double
    public var longitude: Double
    /// Metres above the WGS-84 ellipsoid, as `CLLocation.altitude` gives it.
    public var altitude: Double?
    /// Metres, from `CLLocation.horizontalAccuracy`. Negative means no fix.
    public var horizontalAccuracy: Double?
    /// Metres, from `CLLocation.verticalAccuracy`. Negative means no altitude fix.
    public var verticalAccuracy: Double?
    public var timestamp: Date?

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        timestamp: Date? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.timestamp = timestamp
    }

    /// `true` when the horizontal position can be used at all.
    public var hasValidHorizontalPosition: Bool {
        guard let accuracy = horizontalAccuracy else { return false }
        return accuracy >= 0
    }

    /// `true` when the altitude can be used at all.
    public var hasValidAltitude: Bool {
        guard altitude != nil, let accuracy = verticalAccuracy else { return false }
        return accuracy >= 0
    }

    /// Horizontal accuracy in metres, or `nil` when there is no fix — so a caller
    /// cannot accidentally read `-1` as a one-metre fix.
    public var usableHorizontalAccuracy: Double? {
        hasValidHorizontalPosition ? horizontalAccuracy : nil
    }

    /// Whether the coordinates are inside the valid WGS-84 ranges.
    public var isCoordinateInRange: Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
    }
}

/// Quality of a plane fitted to a LiDAR point cloud, filled in by the non-contact
/// method. Stored here so a LiDAR measurement and a contact measurement share one
/// record shape and can be exported together.
public struct PlaneFitQuality: Equatable, Sendable, Codable {

    /// Points accepted as lying on the plane.
    public var inlierCount: Int
    /// Points considered in total.
    public var consideredCount: Int
    /// Root-mean-square distance of the inliers from the fitted plane, in metres.
    public var rootMeanSquareError: Double
    /// Area of the fitted patch, in square metres.
    public var areaSquareMetres: Double?

    public init(
        inlierCount: Int,
        consideredCount: Int,
        rootMeanSquareError: Double,
        areaSquareMetres: Double? = nil
    ) {
        self.inlierCount = inlierCount
        self.consideredCount = consideredCount
        self.rootMeanSquareError = rootMeanSquareError
        self.areaSquareMetres = areaSquareMetres
    }

    /// Share of the considered points that the plane explains, `0...1`.
    public var inlierFraction: Double {
        consideredCount > 0 ? Double(inlierCount) / Double(consideredCount) : 0
    }
}
