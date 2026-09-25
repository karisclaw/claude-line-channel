import XCTest
@testable import OrientationCore

/// A2 — averaging one burst of samples, and its quality figures.
final class AxialStatisticsTests: XCTestCase {

    func testIdenticalSamplesAverageToThemselvesWithZeroSpread() {
        let plane = PlaneOrientation(dip: 45, dipDirection: 90)
        let summary = AxialStatistics.summarize(planes: Array(repeating: plane, count: 5))!

        XCTAssertEqual(summary.sampleCount, 5)
        XCTAssertEqual(summary.angularStandardDeviation, 0, accuracy: 1e-9)
        XCTAssertEqual(summary.maxAngularDeviation, 0, accuracy: 1e-9)
        XCTAssertEqual(summary.eigenvalues[0], 1, accuracy: 1e-12)
        XCTAssertEqual(summary.meanPlane!.dip, 45, accuracy: 1e-9)
        XCTAssertAzimuthEqual(summary.meanPlane!.dipDirection, 90, accuracy: 1e-9)
    }

    func testSingleSampleIsItsOwnMean() {
        let summary = AxialStatistics.summarize(planes: [PlaneOrientation(dip: 12, dipDirection: 300)])!
        XCTAssertEqual(summary.sampleCount, 1)
        XCTAssertEqual(summary.angularStandardDeviation, 0)
        XCTAssertEqual(summary.meanPlane!.dip, 12, accuracy: 1e-9)
        XCTAssertAzimuthEqual(summary.meanPlane!.dipDirection, 300, accuracy: 1e-9)
    }

    /// A symmetric burst averages back to its centre.
    ///
    /// The mean dip is 44.991°, not exactly 45°: averaging happens on the sphere,
    /// where the mean of unit normals is not the mean of the dip angles. The
    /// expected value here is the spherical answer, and pinning it stops anyone
    /// "fixing" the code into doing arithmetic on angles instead.
    func testSymmetricBurstAveragesToItsCentre() {
        let samples = [
            PlaneOrientation(dip: 43, dipDirection: 90),
            PlaneOrientation(dip: 47, dipDirection: 90),
            PlaneOrientation(dip: 45, dipDirection: 88),
            PlaneOrientation(dip: 45, dipDirection: 92)
        ]
        let summary = AxialStatistics.summarize(planes: samples)!
        XCTAssertEqual(summary.meanPlane!.dip, 44.9912635961, accuracy: 1e-6)
        XCTAssertAzimuthEqual(summary.meanPlane!.dipDirection, 90, accuracy: 1e-6)
        XCTAssertEqual(summary.angularStandardDeviation, 1.9999576883, accuracy: 1e-6)
        XCTAssertEqual(summary.meanAngularDeviation, 1.7070484085, accuracy: 1e-6)
        XCTAssertEqual(summary.maxAngularDeviation, 2.0087364039, accuracy: 1e-6)
    }

    /// The reason averaging goes through the orientation tensor: samples of one
    /// near-vertical joint straddle the up/down flip and carry opposite signs. An
    /// arithmetic mean of those vectors cancels to nearly nothing; the tensor mean
    /// is unaffected.
    func testSignFlippedSamplesGiveTheSameMean() {
        let samples = [
            PlaneOrientation(dip: 43, dipDirection: 90),
            PlaneOrientation(dip: 47, dipDirection: 90),
            PlaneOrientation(dip: 45, dipDirection: 88),
            PlaneOrientation(dip: 45, dipDirection: 92)
        ]
        let straight = AxialStatistics.summarize(samples.map(\.upwardNormal))!
        let flipped = AxialStatistics.summarize(
            samples.enumerated().map { $0.offset.isMultiple(of: 2) ? -$0.element.upwardNormal : $0.element.upwardNormal }
        )!

        XCTAssertEqual(flipped.meanPlane!.dip, straight.meanPlane!.dip, accuracy: 1e-9)
        XCTAssertAzimuthEqual(flipped.meanPlane!.dipDirection, straight.meanPlane!.dipDirection, accuracy: 1e-9)
        XCTAssertEqual(flipped.angularStandardDeviation, straight.angularStandardDeviation, accuracy: 1e-9)

        // The arithmetic mean, for contrast, collapses.
        let arithmetic = samples
            .enumerated()
            .map { $0.offset.isMultiple(of: 2) ? -$0.element.upwardNormal : $0.element.upwardNormal }
            .reduce(Vector3.zero, +) / 4
        XCTAssertLessThan(arithmetic.length, 0.1)
    }

    /// A burst on a near-vertical face averages to one plane whichever face it was
    /// taken from, while the mean *axis* still remembers which direction the phone
    /// actually faced — the attitude is axial, the measured outward direction is not.
    func testNearVerticalBurstAveragesToTheSamePlaneFromEitherFace() {
        let jitter = [-0.3, -0.1, 0.0, 0.2, 0.4].map {
            PlaneOrientation(dip: 90 - abs($0), dipDirection: 90 + $0).upwardNormal
        }
        let east = AxialStatistics.summarize(jitter)!
        let west = AxialStatistics.summarize(jitter.map { -$0 })!

        XCTAssertEqual(east.meanPlane!.dip, 89.8, accuracy: 1e-3)
        XCTAssertEqual(west.meanPlane!, east.meanPlane!)
        XCTAssertAzimuthEqual(east.meanPlane!.dipDirection, 90.04, accuracy: 1e-3)
        XCTAssertEqual(east.angularStandardDeviation, west.angularStandardDeviation, accuracy: 1e-12)

        // The mean axis keeps the sense of the samples it was built from.
        XCTAssertAzimuthEqual(east.meanAxis.azimuth!, 90.04, accuracy: 1e-3)
        XCTAssertAzimuthEqual(west.meanAxis.azimuth!, 270.04, accuracy: 1e-3)
    }

    func testEigenvaluesSumToOneAndDescend() {
        let samples = (0..<10).map { PlaneOrientation(dip: 30 + Double($0), dipDirection: 100 + 2 * Double($0)) }
        let summary = AxialStatistics.summarize(planes: samples)!
        XCTAssertEqual(summary.eigenvalues.reduce(0, +), 1, accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(summary.eigenvalues[0], summary.eigenvalues[1])
        XCTAssertGreaterThanOrEqual(summary.eigenvalues[1], summary.eigenvalues[2])
        XCTAssertGreaterThan(summary.eigenvalues[0], 0.99, "a tight burst should be strongly clustered")
    }

    /// Poles spread evenly around a great circle form a girdle: two equal large
    /// eigenvalues and a third of zero. The set-analysis module reads fabric shape
    /// off exactly this, so the decomposition has to survive the degenerate case.
    func testGirdleFabricEigenvalues() {
        let girdle = [0.0, 30, 60, 90, 120, 150].map {
            PlaneOrientation(dip: 90, dipDirection: $0).upwardNormal
        }
        let summary = AxialStatistics.summarize(girdle)!
        XCTAssertEqual(summary.eigenvalues[0], 0.5, accuracy: 1e-9)
        XCTAssertEqual(summary.eigenvalues[1], 0.5, accuracy: 1e-9)
        XCTAssertEqual(summary.eigenvalues[2], 0, accuracy: 1e-9)
        // The smallest eigenvector is the axis of the girdle — here, vertical.
        XCTAssertEqual(abs(summary.eigenvectors[2].up), 1, accuracy: 1e-9)
    }

    func testLineationsAverageThroughTheSameMachinery() {
        let lines = [
            LineOrientation(trend: 118, plunge: 29),
            LineOrientation(trend: 122, plunge: 31),
            LineOrientation(trend: 120, plunge: 30)
        ]
        let summary = AxialStatistics.summarize(lines: lines)!
        XCTAssertAzimuthEqual(summary.meanLine!.trend, 120, accuracy: 0.2)
        XCTAssertEqual(summary.meanLine!.plunge, 30, accuracy: 0.2)
        XCTAssertLessThan(summary.angularStandardDeviation, 3)
    }

    func testEmptyAndDegenerateInput() {
        XCTAssertNil(AxialStatistics.summarize([]))
        XCTAssertNil(AxialStatistics.summarize([.zero, .zero]))
        // Usable samples survive alongside dropped ones.
        let summary = AxialStatistics.summarize([Vector3(0, 0, 1), .zero])!
        XCTAssertEqual(summary.sampleCount, 1)
    }
}

final class SymmetricMatrix3Tests: XCTestCase {

    func testEigenDecompositionOfADiagonalMatrix() {
        let m = SymmetricMatrix3(m00: 3, m01: 0, m02: 0, m11: 1, m12: 0, m22: 2)
        let eigen = m.eigen()
        XCTAssertEqual(eigen.values[0], 3, accuracy: 1e-12)
        XCTAssertEqual(eigen.values[1], 2, accuracy: 1e-12)
        XCTAssertEqual(eigen.values[2], 1, accuracy: 1e-12)
        XCTAssertEqual(abs(eigen.vectors[0].x), 1, accuracy: 1e-12)
        XCTAssertEqual(abs(eigen.vectors[1].z), 1, accuracy: 1e-12)
        XCTAssertEqual(abs(eigen.vectors[2].y), 1, accuracy: 1e-12)
    }

    func testEigenvectorsSatisfyTheEigenEquation() {
        let m = SymmetricMatrix3(m00: 2, m01: -0.4, m02: 0.7, m11: 1.3, m12: 0.2, m22: 0.9)
        let eigen = m.eigen()
        for (value, vector) in zip(eigen.values, eigen.vectors) {
            let product = Vector3(
                m[0, 0] * vector.x + m[0, 1] * vector.y + m[0, 2] * vector.z,
                m[1, 0] * vector.x + m[1, 1] * vector.y + m[1, 2] * vector.z,
                m[2, 0] * vector.x + m[2, 1] * vector.y + m[2, 2] * vector.z
            )
            XCTAssertVectorEqual(product, vector * value, accuracy: 1e-9)
        }
        XCTAssertEqual(eigen.values.reduce(0, +), m.trace, accuracy: 1e-9)
    }

    func testEigenvectorsAreOrthonormal() {
        let m = SymmetricMatrix3(m00: 0.9, m01: 0.3, m02: -0.2, m11: 0.4, m12: 0.15, m22: 0.7)
        let v = m.eigen().vectors
        for i in 0..<3 {
            XCTAssertEqual(v[i].length, 1, accuracy: 1e-9)
            for j in (i + 1)..<3 {
                XCTAssertEqual(v[i].dot(v[j]), 0, accuracy: 1e-9)
            }
        }
    }

    func testOrientationTensorIsSignIndependent() {
        let axes = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
        let a = SymmetricMatrix3.orientationTensor(of: axes)!
        let b = SymmetricMatrix3.orientationTensor(of: axes.map { -$0 })!
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.trace, 1, accuracy: 1e-12)
        XCTAssertNil(SymmetricMatrix3.orientationTensor(of: []))
    }

    func testSubscriptIsSymmetric() {
        let m = SymmetricMatrix3(m00: 1, m01: 2, m02: 3, m11: 4, m12: 5, m22: 6)
        XCTAssertEqual(m[0, 1], m[1, 0])
        XCTAssertEqual(m[0, 2], m[2, 0])
        XCTAssertEqual(m[1, 2], m[2, 1])
        XCTAssertEqual(m[2, 2], 6)
    }
}
