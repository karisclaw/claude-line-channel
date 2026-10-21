import Foundation

// Quadrant notation for attitudes: `N30°E, 45°SE` for a plane, `45°, S30°W` for a
// lineation. Stored alongside dip/dip-direction, not instead of it — this is the
// form a field notebook and older reports are written in, and importing them means
// reading it back.

extension PlaneOrientation {

    /// The strike as a quadrant bearing, always referenced to north (`N…E` or
    /// `N…W`), which is how strike is written.
    ///
    /// Meaningless for a horizontal plane, which has no strike; check
    /// ``isDipDirectionWellDefined`` first.
    public var quadrantStrike: QuadrantBearing {
        let axis = strikeAxis                       // 0..<180
        return QuadrantBearing(azimuth: axis <= 90 ? axis : axis + 180)
    }

    /// The compass point the plane dips toward — the letter that tells a reader
    /// which side of the strike line the plane goes down.
    ///
    /// `nil` when the plane is horizontal (there is no dip direction) or vertical
    /// (there is no side; both faces are the same plane).
    public var dipQuadrant: CompassQuadrant? {
        guard isDipDirectionWellDefined, !isDipDirectionAmbiguous else { return nil }
        return .nearest(to: dipDirection)
    }

    /// Field shorthand in quadrant notation, e.g. `N30°E, 45°SE`.
    ///
    /// A horizontal plane has no strike to write, and a vertical one has no side to
    /// dip toward, so both are written the way a notebook writes them.
    public var quadrantDescription: String {
        guard isDipDirectionWellDefined else { return "Horizontal" }
        let strikeText = quadrantStrike.axialDescription
        let dipText = QuadrantBearing.format(dip)
        guard let quadrant = dipQuadrant else { return "\(strikeText), \(dipText)°" }
        return "\(strikeText), \(dipText)°\(quadrant.rawValue)"
    }

    /// Reads quadrant notation: `N30E 45SE`, `N30°E, 45°SE`, `E–W, 60°N`,
    /// `N30E, 90` (vertical), `horizontal`.
    ///
    /// The quadrant letters are what resolve the dip direction: a strike line leaves
    /// two perpendicular directions, and the letter picks the nearer one. A letter
    /// lying along the strike itself picks neither, and is rejected rather than
    /// guessed at — that record is genuinely ambiguous and a human has to look at it.
    public init?(quadrantNotation text: String) {
        let characters = QuadrantNotationScanner.normalize(text)
        if characters.isEmpty { return nil }

        if String(characters) == "HORIZONTAL" {
            self.init(dip: 0, dipDirection: 0)
            return
        }

        guard let (strike, afterStrike) = QuadrantNotationScanner.scanBearing(characters, from: 0),
              let (dip, afterDip) = QuadrantNotationScanner.scanNumber(characters, from: afterStrike),
              dip >= 0, dip <= 90
        else { return nil }

        let letters = String(characters[afterDip...])
        let candidates = [
            GeoAngle.normalizedAzimuth(strike.azimuth + 90),
            GeoAngle.normalizedAzimuth(strike.azimuth - 90)
        ]

        if letters.isEmpty {
            // Only a plane with no side to dip toward may omit the quadrant.
            guard dip > 90 - OrientationTolerance.nearVerticalDip
                    || dip < OrientationTolerance.nearHorizontalDip
            else { return nil }
            self.init(dip: dip, dipDirection: candidates[0])
            return
        }

        guard let quadrant = CompassQuadrant(rawValue: letters) else { return nil }
        let separations = candidates.map { GeoAngle.azimuthSeparation($0, quadrant.azimuth) }
        guard abs(separations[0] - separations[1]) > 1e-9 else { return nil }
        self.init(dip: dip, dipDirection: separations[0] < separations[1] ? candidates[0] : candidates[1])
    }
}

extension LineOrientation {

    /// The trend as a quadrant bearing. Directed, unlike a strike: a plunging line
    /// goes down one particular way.
    public var quadrantTrend: QuadrantBearing {
        QuadrantBearing(azimuth: trend)
    }

    /// Field shorthand in quadrant notation, e.g. `45°, S30°W`.
    ///
    /// Plunge first, then the trend — the order lineations are written in, and the
    /// opposite of the plane form, where the strike comes first.
    public var quadrantDescription: String {
        guard isTrendWellDefined else { return "\(QuadrantBearing.format(plunge))°, vertical" }
        return "\(QuadrantBearing.format(plunge))°, \(quadrantTrend.directedDescription)"
    }

    /// Reads quadrant notation for a lineation: `45, S30W`, `45°, S30°W`, `10° N`,
    /// `90, vertical`.
    public init?(quadrantNotation text: String) {
        let characters = QuadrantNotationScanner.normalize(text)
        guard let (plunge, afterPlunge) = QuadrantNotationScanner.scanNumber(characters, from: 0),
              plunge >= 0, plunge <= 90
        else { return nil }

        // A vertical line has no trend to record, so accept the word the formatter
        // writes in its place.
        if String(characters[afterPlunge...]) == "VERTICAL" {
            guard plunge > 90 - OrientationTolerance.nearVerticalPlunge else { return nil }
            self.init(trend: 0, plunge: plunge)
            return
        }

        guard let (trend, end) = QuadrantNotationScanner.scanBearing(characters, from: afterPlunge),
              end == characters.count
        else { return nil }
        self.init(trend: trend.azimuth, plunge: plunge)
    }
}
