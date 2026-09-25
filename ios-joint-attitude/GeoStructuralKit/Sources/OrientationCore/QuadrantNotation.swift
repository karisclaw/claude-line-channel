import Foundation

/// One of the eight compass points, used for the letter that says which side of the
/// strike line a plane dips toward.
public enum CompassQuadrant: String, CaseIterable, Sendable, Codable {
    case north = "N"
    case northeast = "NE"
    case east = "E"
    case southeast = "SE"
    case south = "S"
    case southwest = "SW"
    case west = "W"
    case northwest = "NW"

    public var azimuth: Double {
        switch self {
        case .north: 0
        case .northeast: 45
        case .east: 90
        case .southeast: 135
        case .south: 180
        case .southwest: 225
        case .west: 270
        case .northwest: 315
        }
    }

    /// The compass point closest to an azimuth.
    ///
    /// Derived from the azimuths rather than from the declaration order, so
    /// reordering a case cannot quietly shift every label by 45°.
    public static func nearest(to azimuth: Double) -> CompassQuadrant {
        allCases.min {
            GeoAngle.azimuthSeparation($0.azimuth, azimuth)
                < GeoAngle.azimuthSeparation($1.azimuth, azimuth)
        }!
    }
}

/// A bearing in quadrant form — `N30°E`, `S45°W` — as written in a field notebook.
public struct QuadrantBearing: Equatable, Hashable, Sendable, Codable {

    public enum Meridian: String, CaseIterable, Sendable, Codable {
        case north = "N"
        case south = "S"
    }

    public enum Side: String, CaseIterable, Sendable, Codable {
        case east = "E"
        case west = "W"
    }

    public let meridian: Meridian
    /// Angle away from the meridian, `0...90` degrees.
    public let angle: Double
    public let side: Side

    public init(meridian: Meridian, angle: Double, side: Side) {
        self.meridian = meridian
        self.angle = GeoAngle.clamp(angle, 0, 90)
        self.side = side
    }

    /// The quadrant form of a full azimuth.
    public init(azimuth: Double) {
        let a = GeoAngle.normalizedAzimuth(azimuth)
        switch a {
        case ...90: self.init(meridian: .north, angle: a, side: .east)
        case ...180: self.init(meridian: .south, angle: 180 - a, side: .east)
        case ...270: self.init(meridian: .south, angle: a - 180, side: .west)
        default: self.init(meridian: .north, angle: 360 - a, side: .west)
        }
    }

    /// The full azimuth this bearing denotes, `0..<360`.
    public var azimuth: Double {
        switch (meridian, side) {
        case (.north, .east): GeoAngle.normalizedAzimuth(angle)
        case (.south, .east): GeoAngle.normalizedAzimuth(180 - angle)
        case (.south, .west): GeoAngle.normalizedAzimuth(180 + angle)
        case (.north, .west): GeoAngle.normalizedAzimuth(360 - angle)
        }
    }

    /// A **direction**: `N30°E`, or a bare `N` / `E` / `S` / `W` when it lies on an
    /// axis. Use this for a trend, which points one way.
    public var directedDescription: String {
        if angle < 0.05 { return meridian.rawValue }
        if angle > 89.95 { return side.rawValue }
        return "\(meridian.rawValue)\(QuadrantBearing.format(angle))°\(side.rawValue)"
    }

    /// A **line**: `N30°E`, or `N–S` / `E–W` when it lies on an axis. Use this for a
    /// strike, which has no preferred direction along it.
    public var axialDescription: String {
        if angle < 0.05 { return "N–S" }
        if angle > 89.95 { return "E–W" }
        return "\(meridian.rawValue)\(QuadrantBearing.format(angle))°\(side.rawValue)"
    }

    static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
    }

    /// Parses `N30E`, `N30°E`, `N 30 E`, `N–S`, `E–W`, and the bare cardinals.
    public init?(parsing text: String) {
        let characters = QuadrantNotationScanner.normalize(text)
        guard let (bearing, end) = QuadrantNotationScanner.scanBearing(characters, from: 0),
              end == characters.count
        else { return nil }
        self = bearing
    }
}

extension QuadrantBearing: CustomStringConvertible {
    /// Defaults to the directed form; a strike should ask for ``axialDescription``.
    public var description: String { directedDescription }
}

/// Shared text handling for quadrant notation.
///
/// Hand-written rather than regex-based: this input comes off field notebooks and
/// arrives spaced and punctuated every possible way, and a scanner that simply
/// ignores separators handles all of it with nothing subtle to get wrong.
enum QuadrantNotationScanner {

    /// Uppercases, drops separators, folds every kind of dash to `-`.
    static func normalize(_ text: String) -> [Character] {
        var result: [Character] = []
        for character in text.uppercased() {
            switch character {
            case "°", ",", "/", "→", ";":
                continue
            case "-", "–", "—", "_":
                result.append("-")
            case let c where c.isWhitespace:
                continue
            default:
                result.append(character)
            }
        }
        return result
    }

    /// Scans a bearing and returns it with the index just past it.
    static func scanBearing(_ characters: [Character], from start: Int) -> (QuadrantBearing, Int)? {
        guard start < characters.count else { return nil }
        let first = characters[start]
        let nextIsDigit = start + 1 < characters.count && characters[start + 1].isNumber

        // N30E / S45W — try this first so the leading letter is not mistaken for a
        // bare cardinal.
        if nextIsDigit, let meridian = QuadrantBearing.Meridian(rawValue: String(first)) {
            guard let (angle, afterAngle) = scanNumber(characters, from: start + 1),
                  afterAngle < characters.count,
                  let side = QuadrantBearing.Side(rawValue: String(characters[afterAngle])),
                  angle >= 0, angle <= 90
            else { return nil }
            return (QuadrantBearing(meridian: meridian, angle: angle, side: side), afterAngle + 1)
        }

        if matches(characters, from: start, "N-S") {
            return (QuadrantBearing(meridian: .north, angle: 0, side: .east), start + 3)
        }
        if matches(characters, from: start, "E-W") {
            return (QuadrantBearing(meridian: .north, angle: 90, side: .east), start + 3)
        }

        // Bare cardinals.
        switch first {
        case "N": return (QuadrantBearing(meridian: .north, angle: 0, side: .east), start + 1)
        case "S": return (QuadrantBearing(meridian: .south, angle: 0, side: .east), start + 1)
        case "E": return (QuadrantBearing(meridian: .north, angle: 90, side: .east), start + 1)
        case "W": return (QuadrantBearing(meridian: .north, angle: 90, side: .west), start + 1)
        default: return nil
        }
    }

    static func scanNumber(_ characters: [Character], from start: Int) -> (Double, Int)? {
        var index = start
        var digits = ""
        while index < characters.count, characters[index].isNumber || characters[index] == "." {
            digits.append(characters[index])
            index += 1
        }
        guard let value = Double(digits) else { return nil }
        return (value, index)
    }

    static func matches(_ characters: [Character], from start: Int, _ pattern: String) -> Bool {
        let wanted = Array(pattern)
        guard start + wanted.count <= characters.count else { return false }
        return Array(characters[start..<(start + wanted.count)]) == wanted
    }
}
