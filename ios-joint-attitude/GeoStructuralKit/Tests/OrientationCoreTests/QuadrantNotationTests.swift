import XCTest
@testable import OrientationCore

final class QuadrantBearingTests: XCTestCase {

    func testAzimuthToQuadrantAndBack() {
        for azimuth in stride(from: 0.0, to: 360.0, by: 1.0) {
            let bearing = QuadrantBearing(azimuth: azimuth)
            XCTAssertGreaterThanOrEqual(bearing.angle, 0)
            XCTAssertLessThanOrEqual(bearing.angle, 90)
            XCTAssertAzimuthEqual(bearing.azimuth, azimuth, accuracy: 1e-9)
        }
    }

    func testTheFourQuadrants() {
        XCTAssertEqual(QuadrantBearing(azimuth: 30), QuadrantBearing(meridian: .north, angle: 30, side: .east))
        XCTAssertEqual(QuadrantBearing(azimuth: 150), QuadrantBearing(meridian: .south, angle: 30, side: .east))
        XCTAssertEqual(QuadrantBearing(azimuth: 210), QuadrantBearing(meridian: .south, angle: 30, side: .west))
        XCTAssertEqual(QuadrantBearing(azimuth: 330), QuadrantBearing(meridian: .north, angle: 30, side: .west))
    }

    /// A direction on an axis is written as a cardinal; a *line* on the same axis is
    /// written with a dash, because it has no preferred direction along it.
    func testDirectedAndAxialDescriptionsDifferOnlyOnTheAxes() {
        XCTAssertEqual(QuadrantBearing(azimuth: 0).directedDescription, "N")
        XCTAssertEqual(QuadrantBearing(azimuth: 90).directedDescription, "E")
        XCTAssertEqual(QuadrantBearing(azimuth: 180).directedDescription, "S")
        XCTAssertEqual(QuadrantBearing(azimuth: 270).directedDescription, "W")
        XCTAssertEqual(QuadrantBearing(azimuth: 0).axialDescription, "N–S")
        XCTAssertEqual(QuadrantBearing(azimuth: 90).axialDescription, "E–W")
        XCTAssertEqual(QuadrantBearing(azimuth: 30).directedDescription, "N30°E")
        XCTAssertEqual(QuadrantBearing(azimuth: 30).axialDescription, "N30°E")
        XCTAssertEqual(QuadrantBearing(azimuth: 217.5).directedDescription, "S37.5°W")
    }

    func testParsingAcceptsEveryWayAFieldNotebookWritesIt() {
        for text in ["N30E", "N30°E", "n 30 e", "N 30° E", "N30.0E"] {
            XCTAssertEqual(QuadrantBearing(parsing: text)?.azimuth, 30, "failed on \(text)")
        }
        XCTAssertEqual(QuadrantBearing(parsing: "S45W")?.azimuth, 225)
        XCTAssertEqual(QuadrantBearing(parsing: "N–S")?.azimuth, 0)
        XCTAssertEqual(QuadrantBearing(parsing: "N-S")?.azimuth, 0)
        XCTAssertEqual(QuadrantBearing(parsing: "E-W")?.azimuth, 90)
        XCTAssertEqual(QuadrantBearing(parsing: "W")?.azimuth, 270)
        XCTAssertEqual(QuadrantBearing(parsing: "S")?.azimuth, 180)
    }

    func testParsingRejectsNonsense() {
        for text in ["", "X30E", "N30X", "N100E", "30NE", "NE30", "N30", "N30E5"] {
            XCTAssertNil(QuadrantBearing(parsing: text), "should not have parsed \(text)")
        }
    }

    func testNearestCompassQuadrant() {
        XCTAssertEqual(CompassQuadrant.nearest(to: 0), .north)
        XCTAssertEqual(CompassQuadrant.nearest(to: 120), .southeast)
        XCTAssertEqual(CompassQuadrant.nearest(to: 200), .south)
        XCTAssertEqual(CompassQuadrant.nearest(to: 315), .northwest)
        XCTAssertEqual(CompassQuadrant.nearest(to: 359), .north)
        for quadrant in CompassQuadrant.allCases {
            XCTAssertEqual(CompassQuadrant.nearest(to: quadrant.azimuth), quadrant)
        }
    }
}

final class QuadrantAttitudeTests: XCTestCase {

    /// The worked examples, for eyeballing against a field notebook.
    func testKnownAttitudesInQuadrantNotation() {
        let cases: [(Double, Double, String)] = [
            (45, 120, "N30°E, 45°SE"),
            (45, 240, "N30°W, 45°SW"),
            (30, 90, "N–S, 30°E"),
            (60, 0, "E–W, 60°N"),
            (20, 315, "N45°E, 20°NW"),
            (75, 200, "N70°W, 75°S"),
            (90, 90, "N–S, 90°"),
            (0, 0, "Horizontal")
        ]
        for (dip, dipDirection, expected) in cases {
            XCTAssertEqual(
                PlaneOrientation(dip: dip, dipDirection: dipDirection).quadrantDescription,
                expected,
                "for \(dip)/\(dipDirection)"
            )
        }
    }

    /// Quadrant notation must survive a round trip for every inclined plane: the
    /// letters carry exactly enough information to put the dip direction back.
    func testQuadrantNotationRoundTripsForEveryInclinedPlane() {
        for dip in [1.0, 5, 15, 30, 45, 60, 75, 85, 89] {
            for dipDirection in stride(from: 0.0, to: 360.0, by: 3.0) {
                let plane = PlaneOrientation(dip: dip, dipDirection: dipDirection)
                guard let parsed = PlaneOrientation(quadrantNotation: plane.quadrantDescription) else {
                    return XCTFail("could not read back \(plane.quadrantDescription) from \(plane)")
                }
                XCTAssertEqual(parsed.dip, dip, accuracy: 1e-9)
                XCTAssertAzimuthEqual(parsed.dipDirection, dipDirection, accuracy: 1e-9)
            }
        }
    }

    /// A vertical plane has no side to dip toward, so the notation carries no
    /// quadrant and reads back as the same plane rather than the same description.
    func testVerticalPlaneRoundTripsToTheSamePlane() {
        for dipDirection in [0.0, 90, 180, 270] {
            let plane = PlaneOrientation(dip: 90, dipDirection: dipDirection)
            let parsed = PlaneOrientation(quadrantNotation: plane.quadrantDescription)!
            XCTAssertEqual(parsed.dip, 90, accuracy: 1e-9)
            XCTAssertEqual(parsed.angle(to: plane), 0, accuracy: 1e-5)
        }
        // A notebook that did record a side for a vertical plane keeps it.
        let recorded = PlaneOrientation(quadrantNotation: "N30E, 90SE")!
        XCTAssertEqual(recorded.dip, 90, accuracy: 1e-9)
        XCTAssertAzimuthEqual(recorded.dipDirection, 120, accuracy: 1e-9)
    }

    func testHorizontalPlaneRoundTrips() {
        let parsed = PlaneOrientation(quadrantNotation: "Horizontal")!
        XCTAssertEqual(parsed.dip, 0, accuracy: 1e-12)
        XCTAssertFalse(parsed.isDipDirectionWellDefined)
    }

    func testParsingAcceptsTheUsualWrittenForms() {
        let expected = PlaneOrientation(dip: 45, dipDirection: 120)
        for text in ["N30E, 45SE", "N30°E, 45°SE", "n 30 e 45 se", "N30E/45SE", "N30E 45 SE"] {
            guard let parsed = PlaneOrientation(quadrantNotation: text) else {
                return XCTFail("failed to parse \(text)")
            }
            XCTAssertEqual(parsed.dip, expected.dip, accuracy: 1e-9, "for \(text)")
            XCTAssertAzimuthEqual(parsed.dipDirection, expected.dipDirection, accuracy: 1e-9, "for \(text)")
        }
    }

    /// A dip letter lying along the strike picks neither side, so the record is
    /// genuinely ambiguous. Rejecting it is the point — guessing would silently
    /// invent a dip direction 90° from the truth.
    func testDipQuadrantAlongTheStrikeIsRejected() {
        XCTAssertNil(PlaneOrientation(quadrantNotation: "N45E, 45NE"))
        XCTAssertNil(PlaneOrientation(quadrantNotation: "N45E, 45SW"))
        XCTAssertNotNil(PlaneOrientation(quadrantNotation: "N45E, 45SE"))
        XCTAssertNotNil(PlaneOrientation(quadrantNotation: "N45E, 45NW"))
    }

    /// An inclined plane written without a dip side cannot be resolved, and is not
    /// guessed at.
    func testInclinedPlaneWithoutADipQuadrantIsRejected() {
        XCTAssertNil(PlaneOrientation(quadrantNotation: "N30E, 45"))
        XCTAssertNotNil(PlaneOrientation(quadrantNotation: "N30E, 90"))
    }

    func testQuadrantParsingRejectsNonsense() {
        for text in ["", "N30E, 45XY", "N30E, 120SE", "hello", "45SE"] {
            XCTAssertNil(PlaneOrientation(quadrantNotation: text), "should not have parsed \(text)")
        }
    }

    func testDipQuadrantIsAbsentWhereItHasNoMeaning() {
        XCTAssertEqual(PlaneOrientation(dip: 45, dipDirection: 120).dipQuadrant, .southeast)
        XCTAssertNil(PlaneOrientation(dip: 0, dipDirection: 120).dipQuadrant)
        XCTAssertNil(PlaneOrientation(dip: 90, dipDirection: 120).dipQuadrant)
    }

    func testLineationQuadrantNotation() {
        XCTAssertEqual(LineOrientation(trend: 210, plunge: 45).quadrantDescription, "45°, S30°W")
        XCTAssertEqual(LineOrientation(trend: 0, plunge: 10).quadrantDescription, "10°, N")
        XCTAssertEqual(LineOrientation(trend: 0, plunge: 90).quadrantDescription, "90°, vertical")

        for trend in stride(from: 0.0, to: 360.0, by: 3.0) {
            for plunge in [0.0, 12, 45, 78, 89] {
                let line = LineOrientation(trend: trend, plunge: plunge)
                guard let parsed = LineOrientation(quadrantNotation: line.quadrantDescription) else {
                    return XCTFail("could not read back \(line.quadrantDescription)")
                }
                XCTAssertEqual(parsed.plunge, plunge, accuracy: 1e-9)
                XCTAssertAzimuthEqual(parsed.trend, trend, accuracy: 1e-9)
            }
        }

        let vertical = LineOrientation(quadrantNotation: "90, vertical")!
        XCTAssertEqual(vertical.plunge, 90, accuracy: 1e-9)
        XCTAssertFalse(vertical.isTrendWellDefined)
    }
}
