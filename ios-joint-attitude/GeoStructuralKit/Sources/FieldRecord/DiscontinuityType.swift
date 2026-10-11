import Foundation

/// The kind of discontinuity a measurement is of.
public enum DiscontinuityType: String, CaseIterable, Sendable, Codable {
    /// 節理 — a joint, with no visible displacement.
    case joint
    /// 層面 — a bedding plane.
    case bedding
    /// 斷層 — a fault, with displacement.
    case fault
    /// 葉理 — foliation in a metamorphic rock.
    case foliation
    /// 劈理 — cleavage.
    case cleavage
    /// 脈 — a vein or a mineral-filled fracture.
    case vein
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
