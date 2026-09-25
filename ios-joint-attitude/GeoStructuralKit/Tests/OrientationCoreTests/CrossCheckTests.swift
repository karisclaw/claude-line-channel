import XCTest
@testable import OrientationCore

/// Checks that verify the conversions against relations established **outside** this
/// package — textbook identities and independent constructions — rather than against
/// the package's own arithmetic. A formula can round-trip perfectly against itself
/// and still be wrong; these are the tests that would catch that.
final class CrossCheckTests: XCTestCase {

    /// Textbook relation between a plane and its lower-hemisphere pole:
    /// `pole trend = dip direction + 180`, `pole plunge = 90 − dip`.
    ///
    /// This is the standard stereonet identity, stated independently of how this
    /// package computes anything, and it pins the dip-direction sign convention from
    /// a second direction.
    func testPoleTrendAndPlungeMatchTheStandardStereonetRelation() {
        for dip in [0.0, 10, 30, 45, 60, 89, 90] {
            for dipDirection in [0.0, 37, 90, 180, 271, 359] {
                let plane = PlaneOrientation(dip: dip, dipDirection: dipDirection)
                let pole = LineOrientation(measuredAxis: plane.pole)!
                XCTAssertEqual(pole.plunge, 90 - dip, accuracy: 1e-9)
                if dip > OrientationTolerance.nearHorizontalDip, dip < 90 - OrientationTolerance.nearVerticalDip {
                    XCTAssertAzimuthEqual(pole.trend, dipDirection + 180, accuracy: 1e-9)
                }
            }
        }
    }

    /// The apparent dip must equal the plunge of the line where the plane meets the
    /// vertical section — computed here by intersecting two planes, which shares no
    /// code with `tan(apparent) = tan(dip)·cos(β)`.
    func testApparentDipEqualsThePlungeOfTheSectionIntersection() {
        for dip in [5.0, 20, 45, 70, 88] {
            for dipDirection in [0.0, 90, 200, 330] {
                let plane = PlaneOrientation(dip: dip, dipDirection: dipDirection)
                for trend in [0.0, 30, 60, 120, 200, 300] {
                    // A vertical plane whose strike runs along `trend` is the section.
                    let section = PlaneOrientation(dip: 90, dipDirection: trend + 90)
                    guard let line = plane.intersection(with: section) else { continue }
                    XCTAssertEqual(
                        abs(plane.apparentDip(inVerticalSectionAlong: trend)), line.plunge,
                        accuracy: 1e-9,
                        "apparent dip disagrees with the section intersection at \(plane) along \(trend)"
                    )
                }
            }
        }
    }

    /// Whatever the intersection of two planes is, it has to lie in both of them.
    func testIntersectionLiesInBothPlanes() {
        // A deterministic sweep rather than random input, so a failure reproduces.
        for dipA in stride(from: 5.0, through: 85.0, by: 20.0) {
            for dipDirectionA in stride(from: 0.0, to: 360.0, by: 60.0) {
                for dipB in stride(from: 5.0, through: 85.0, by: 20.0) {
                    for dipDirectionB in stride(from: 30.0, to: 360.0, by: 60.0) {
                        let a = PlaneOrientation(dip: dipA, dipDirection: dipDirectionA)
                        let b = PlaneOrientation(dip: dipB, dipDirection: dipDirectionB)
                        guard let line = a.intersection(with: b) else { continue }
                        XCTAssertEqual(a.upwardNormal.dot(line.downPlungeVector), 0, accuracy: 1e-9)
                        XCTAssertEqual(b.upwardNormal.dot(line.downPlungeVector), 0, accuracy: 1e-9)
                        XCTAssertTrue(a.contains(line, tolerance: 1e-6))
                        XCTAssertTrue(b.contains(line, tolerance: 1e-6))
                    }
                }
            }
        }
    }

    /// Nearly parallel planes must report no intersection rather than a confident
    /// random trend: the cross product of their normals is rounding error by then.
    func testNearlyParallelPlanesHaveNoUsableIntersection() {
        let a = PlaneOrientation(dip: 45, dipDirection: 90)
        XCTAssertNil(a.intersection(with: a))
        XCTAssertNil(a.intersection(with: PlaneOrientation(dip: 45, dipDirection: 90.00001)))
        XCTAssertNotNil(a.intersection(with: PlaneOrientation(dip: 45, dipDirection: 91)))
    }

    /// Every eigenvector really is one: `Av = λv`, the eigenvectors are orthonormal,
    /// and the eigenvalues sum to the trace.
    func testEigenDecompositionSatisfiesItsDefiningProperties() {
        // Deterministic pseudo-random symmetric matrices.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53) * 4 - 2
        }

        for _ in 0..<200 {
            let m = SymmetricMatrix3(
                m00: next(), m01: next(), m02: next(),
                m11: next(), m12: next(), m22: next()
            )
            let eigen = m.eigen()

            for (value, vector) in zip(eigen.values, eigen.vectors) {
                let product = Vector3(
                    m[0, 0] * vector.x + m[0, 1] * vector.y + m[0, 2] * vector.z,
                    m[1, 0] * vector.x + m[1, 1] * vector.y + m[1, 2] * vector.z,
                    m[2, 0] * vector.x + m[2, 1] * vector.y + m[2, 2] * vector.z
                )
                XCTAssertVectorEqual(product, vector * value, accuracy: 1e-9)
            }

            for i in 0..<3 {
                XCTAssertEqual(eigen.vectors[i].length, 1, accuracy: 1e-9)
                for j in (i + 1)..<3 {
                    XCTAssertEqual(eigen.vectors[i].dot(eigen.vectors[j]), 0, accuracy: 1e-9)
                }
            }

            XCTAssertEqual(eigen.values.reduce(0, +), m.trace, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(eigen.values[0], eigen.values[1])
            XCTAssertGreaterThanOrEqual(eigen.values[1], eigen.values[2])
        }
    }

    /// An axis and its negation must always reduce to the same hemisphere
    /// representative — including on the equator, where neither points up and
    /// `0.0` and `-0.0` do not compare as different.
    func testHemisphereRepresentativeIsSignIndependentIncludingOnTheEquator() {
        let axes = [
            Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
            Vector3(1, 1, 0), Vector3(0, 1, 1), Vector3(-1, 0, 0),
            Vector3(0, -1, 0), Vector3(0.3, -0.7, 0), Vector3(-0.2, 0.4, -0.9)
        ]
        for axis in axes {
            let a = axis.upperHemisphereRepresentative!
            let b = (-axis).upperHemisphereRepresentative!
            XCTAssertVectorEqual(a, b, accuracy: 1e-15)
            XCTAssertGreaterThanOrEqual(a.up, 0)
            XCTAssertVectorEqual(axis.lowerHemisphereRepresentative!, -a, accuracy: 1e-15)
        }
        XCTAssertNil(Vector3.zero.upperHemisphereRepresentative)
    }

    /// The same, at the level that matters: a vertical plane whose normal has an
    /// exactly zero vertical component still reports one attitude from either face.
    func testExactlyHorizontalNormalGivesTheSameAttitudeFromEitherFace() {
        for normal in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0.6, -0.8, 0)] {
            let a = PlaneOrientation(measuredNormal: normal)!
            let b = PlaneOrientation(measuredNormal: -normal)!
            XCTAssertEqual(a, b, "±\(normal) gave \(a) and \(b)")
            XCTAssertEqual(a.dip, 90, accuracy: 1e-12)
        }
        // And a horizontal lineation resolves to one trend from either end.
        for axis in [Vector3(1, 0, 0), Vector3(0.6, -0.8, 0)] {
            XCTAssertEqual(
                LineOrientation(measuredAxis: axis)!,
                LineOrientation(measuredAxis: -axis)!
            )
        }
    }

    /// A tilted plane's dip must equal the angle between its own normal and vertical,
    /// and its strike must be horizontal — both checked without going through the
    /// dip/dip-direction arithmetic.
    func testDipEqualsTheNormalsAngleFromVerticalAndStrikeIsHorizontal() {
        for dip in stride(from: 0.0, through: 90.0, by: 7.5) {
            for dipDirection in stride(from: 0.0, to: 360.0, by: 45.0) {
                let plane = PlaneOrientation(dip: dip, dipDirection: dipDirection)
                XCTAssertEqual(plane.upwardNormal.angle(to: .upAxis), dip, accuracy: 1e-9)
                XCTAssertEqual(plane.strikeVector.up, 0, accuracy: 1e-15)
                XCTAssertEqual(plane.dipVector.angle(to: .downAxis), 90 - dip, accuracy: 1e-9)
            }
        }
    }
}
