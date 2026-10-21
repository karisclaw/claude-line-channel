import XCTest
import OrientationCore
@testable import FabricAnalysis

final class StereonetProjectionTests: XCTestCase {

    /// Both projections put the vertical at the centre and the horizontal on the
    /// primitive. If either end drifts, every plotted point is in the wrong place.
    func testBothProjectionsAgreeAtTheCentreAndThePrimitive() {
        for projection in StereonetProjection.allCases {
            XCTAssertEqual(projection.radius(forAngleFromCentre: 0), 0, accuracy: 1e-12)
            XCTAssertEqual(projection.radius(forAngleFromCentre: 90), 1, accuracy: 1e-12)
        }
    }

    func testKnownProjectionRadii() {
        let schmidt = StereonetProjection.equalArea
        let wulff = StereonetProjection.equalAngle
        // √2·sin(θ/2) and tan(θ/2).
        XCTAssertEqual(schmidt.radius(forAngleFromCentre: 30), 0.366025403784, accuracy: 1e-10)
        XCTAssertEqual(schmidt.radius(forAngleFromCentre: 60), 0.707106781187, accuracy: 1e-10)
        XCTAssertEqual(wulff.radius(forAngleFromCentre: 30), 0.267949192431, accuracy: 1e-10)
        XCTAssertEqual(wulff.radius(forAngleFromCentre: 60), 0.577350269190, accuracy: 1e-10)
    }

    /// The property the whole density module rests on: in the equal-area projection, a
    /// spherical cap's share of the hemisphere equals its projected circle's share of the
    /// primitive disc. So `r² = 1 − cos ρ`.
    func testEqualAreaProjectionPreservesArea() {
        for capRadius in [5.0, 15, 30, 45, 60, 90] {
            let areaFraction = 1 - cos(GeoAngle.radians(fromDegrees: capRadius))
            let projected = StereonetProjection.equalArea.radius(forAngleFromCentre: capRadius)
            XCTAssertEqual(projected * projected, areaFraction, accuracy: 1e-12, "at ρ = \(capRadius)°")
        }
    }

    /// The equal-angle projection does **not** preserve area, which is exactly why
    /// density is never counted on it.
    func testEqualAngleProjectionDoesNotPreserveArea() {
        let capRadius = 30.0
        let areaFraction = 1 - cos(GeoAngle.radians(fromDegrees: capRadius))
        let projected = StereonetProjection.equalAngle.radius(forAngleFromCentre: capRadius)
        XCTAssertGreaterThan(abs(projected * projected - areaFraction), 0.05)
    }

    func testRadiusAndAngleAreInverses() {
        for projection in StereonetProjection.allCases {
            for theta in stride(from: 0.0, through: 90.0, by: 1.0) {
                let radius = projection.radius(forAngleFromCentre: theta)
                XCTAssertEqual(
                    projection.angleFromCentre(forRadius: radius), theta,
                    accuracy: 1e-9, "\(projection) at \(theta)°"
                )
            }
        }
    }
}

final class StereonetPlottingTests: XCTestCase {

    func testVerticalAxisPlotsAtTheCentreAndHorizontalOnThePrimitive() {
        for projection in StereonetProjection.allCases {
            let vertical = Stereonet.project(axis: Vector3(0, 0, -1), using: projection)!
            XCTAssertEqual(vertical.radius, 0, accuracy: 1e-12)

            let horizontal = Stereonet.project(axis: Vector3.northAxis, using: projection)!
            XCTAssertEqual(horizontal.radius, 1, accuracy: 1e-9)
        }
    }

    /// North is up on the plot and east is to the right, so a horizontal axis lands on the
    /// primitive at its own azimuth.
    func testAzimuthIsMeasuredClockwiseFromTheTop() {
        let cases: [(Double, Double, Double)] = [
            (0, 0, 1),      // north: top
            (90, 1, 0),     // east: right
            (180, 0, -1),   // south: bottom
            (270, -1, 0)    // west: left
        ]
        for (trend, east, north) in cases {
            let point = Stereonet.project(line: LineOrientation(trend: trend, plunge: 0))
            XCTAssertEqual(point.east, east, accuracy: 1e-9, "trend \(trend)")
            XCTAssertEqual(point.north, north, accuracy: 1e-9, "trend \(trend)")
            XCTAssertEqual(point.azimuth!, trend, accuracy: 1e-9)
        }
    }

    /// An axis and its opposite are one datum, so they must land on one point. Without
    /// this the whole module is plotting vectors, not axes.
    func testAnAxisAndItsOppositePlotIdentically() {
        for dip in stride(from: 0.0, through: 90.0, by: 10.0) {
            for dipDirection in stride(from: 0.0, to: 360.0, by: 30.0) {
                let plane = PlaneOrientation(dip: dip, dipDirection: dipDirection)
                for projection in StereonetProjection.allCases {
                    let up = Stereonet.project(axis: plane.upwardNormal, using: projection)!
                    let down = Stereonet.project(axis: plane.pole, using: projection)!
                    XCTAssertEqual(up.east, down.east, accuracy: 1e-12)
                    XCTAssertEqual(up.north, down.north, accuracy: 1e-12)
                }
            }
        }
    }

    func testProjectionRoundTripsThroughItsInverse() {
        for projection in StereonetProjection.allCases {
            for dip in stride(from: 0.0, through: 90.0, by: 10.0) {
                for dipDirection in stride(from: 0.0, to: 360.0, by: 20.0) {
                    let pole = PlaneOrientation(dip: dip, dipDirection: dipDirection).pole
                    let point = Stereonet.project(axis: pole, using: projection)!
                    let recovered = Stereonet.axis(at: point, using: projection)!
                    XCTAssertLessThan(
                        (recovered - pole.lowerHemisphereRepresentative!).length, 1e-9,
                        "\(projection) at \(dip)/\(dipDirection)"
                    )
                }
            }
        }
    }

    /// A lasso drawn past the edge of the net reports that it went outside rather than
    /// wrapping silently onto the far side.
    func testPointsOutsideThePrimitiveHaveNoAxis() {
        XCTAssertNil(Stereonet.axis(at: StereonetPoint(east: 1.5, north: 0)))
        XCTAssertNil(Stereonet.axis(at: StereonetPoint(east: 0.8, north: 0.8)))
        XCTAssertNotNil(Stereonet.axis(at: StereonetPoint(east: 0.7, north: 0.7)))
    }

    func testDegenerateAxisDoesNotPlot() {
        XCTAssertNil(Stereonet.project(axis: .zero))
        XCTAssertNil(Stereonet.project(axis: Vector3(.nan, 0, 0)))
    }

    // MARK: Great circles

    /// A plane's trace must lie in the plane, start and end on the primitive at the
    /// strike line, and pass through the dip direction.
    func testGreatCircleLiesInThePlaneAndSpansTheStrikeLine() {
        let plane = PlaneOrientation(dip: 50, dipDirection: 120)
        let trace = Stereonet.greatCircle(of: plane)
        XCTAssertGreaterThan(trace.count, 100)

        for point in trace {
            XCTAssertTrue(point.isInsidePrimitive)
            let axis = Stereonet.axis(at: point)!
            XCTAssertEqual(
                axis.dot(plane.upwardNormal), 0, accuracy: 1e-9,
                "a point on the trace must lie in the plane"
            )
        }

        XCTAssertEqual(trace.first!.radius, 1, accuracy: 1e-9, "starts on the primitive")
        XCTAssertEqual(trace.last!.radius, 1, accuracy: 1e-9, "ends on the primitive")
        XCTAssertEqual(trace.first!.azimuth!, plane.strike, accuracy: 1e-6)

        // The midpoint of the sweep is the dip direction.
        let middle = trace[trace.count / 2]
        XCTAssertEqual(middle.azimuth!, plane.dipDirection, accuracy: 1)
    }

    /// A vertical plane's trace is a diameter of the net.
    func testVerticalPlaneTracesADiameter() {
        let trace = Stereonet.greatCircle(of: PlaneOrientation(dip: 90, dipDirection: 90))
        for point in trace {
            XCTAssertEqual(point.east, 0, accuracy: 1e-9, "a north-striking vertical plane is the N–S diameter")
        }
        XCTAssertEqual(trace.map(\.north).max()!, 1, accuracy: 1e-9)
        XCTAssertEqual(trace.map(\.north).min()!, -1, accuracy: 1e-9)
    }

    /// A horizontal plane's trace is the primitive. Half of it would look like a mistake,
    /// so the full circle comes back.
    func testHorizontalPlaneTracesTheWholePrimitive() {
        let trace = Stereonet.greatCircle(of: PlaneOrientation(dip: 0, dipDirection: 0))
        for point in trace {
            XCTAssertEqual(point.radius, 1, accuracy: 1e-9)
        }
        let azimuths = trace.compactMap(\.azimuth)
        XCTAssertLessThan(azimuths.min()!, 10, "the trace should sweep the whole circle")
        XCTAssertGreaterThan(azimuths.max()!, 350)
    }

    // MARK: Small circles

    /// A cone well inside the lower hemisphere is one closed loop, every point of it at
    /// the right angle from the axis.
    func testSmallCircleEntirelyBelowIsOneLoop() {
        let axis = LineOrientation(trend: 40, plunge: 70).downPlungeVector
        let polylines = Stereonet.smallCircle(about: axis, angle: 10)
        XCTAssertEqual(polylines.count, 1)

        for point in polylines[0] {
            let direction = Stereonet.axis(at: point)!
            XCTAssertEqual(direction.axialAngle(to: axis), 10, accuracy: 1e-6)
        }
    }

    /// A cone that crosses the horizontal comes back as two arcs: the part that would sit
    /// above the horizon is folded to its antipode and appears on the far side of the net.
    /// Joining them would draw a line across the plot that means nothing.
    func testSmallCircleCrossingTheHorizonSplitsIntoTwoArcs() {
        let axis = LineOrientation(trend: 90, plunge: 3).downPlungeVector
        let polylines = Stereonet.smallCircle(about: axis, angle: 15)
        XCTAssertEqual(polylines.count, 2, "got \(polylines.count) arcs")

        for polyline in polylines {
            for point in polyline {
                XCTAssertTrue(point.isInsidePrimitive)
                let direction = Stereonet.axis(at: point)!
                XCTAssertEqual(
                    direction.axialAngle(to: axis), 15, accuracy: 1e-6,
                    "every point stays on the cone, folded or not"
                )
            }
        }
    }

    func testSmallCircleRejectsNonsense() {
        XCTAssertTrue(Stereonet.smallCircle(about: .zero, angle: 10).isEmpty)
        XCTAssertTrue(Stereonet.smallCircle(about: .upAxis, angle: 0).isEmpty)
        XCTAssertTrue(Stereonet.smallCircle(about: .upAxis, angle: 200).isEmpty)
    }

    func testPrimitiveIsAClosedUnitCircle() {
        let circle = Stereonet.primitive()
        for point in circle {
            XCTAssertEqual(point.radius, 1, accuracy: 1e-12)
        }
        XCTAssertEqual(circle.first!.east, circle.last!.east, accuracy: 1e-12)
        XCTAssertEqual(circle.first!.north, circle.last!.north, accuracy: 1e-12)
    }
}
