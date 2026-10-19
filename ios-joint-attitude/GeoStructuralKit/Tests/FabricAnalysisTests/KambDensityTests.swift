import XCTest
import OrientationCore
@testable import FabricAnalysis

final class KambParameterTests: XCTestCase {

    /// The two independent routes to the counting circle must agree.
    ///
    /// Statistically, `E = 3σ` forces `a = 9/(N+9)`. Geometrically, the equal-area
    /// projection preserves area, so the circle's projected radius is `√a`, which is the
    /// `3/√(N+9)` usually quoted. Neither derivation knows about the other, so their
    /// agreement is a free check on both.
    func testTheTwoDerivationsOfTheCountingCircleAgree() {
        for sampleCount in [20, 50, 100, 200, 500, 1000] {
            let parameters = KambParameters(sampleCount: sampleCount)!
            let quoted = 3 / Double(sampleCount + 9).squareRoot()
            XCTAssertEqual(
                parameters.projectedRadiusFraction, quoted, accuracy: 1e-12,
                "at N = \(sampleCount)"
            )
        }
    }

    /// The criterion itself: the expected count is three standard deviations.
    func testTheExpectedCountIsThreeSigma() {
        for sampleCount in [20, 50, 100, 200, 500, 1000, 5000] {
            let parameters = KambParameters(sampleCount: sampleCount)!
            XCTAssertEqual(
                parameters.expectedCount / parameters.standardDeviation, 3,
                accuracy: 1e-9, "at N = \(sampleCount)"
            )
        }
    }

    func testTheCriterionIsConfigurable() {
        for criterion in [2.0, 3, 4] {
            let parameters = KambParameters(sampleCount: 200, sigmaCriterion: criterion)!
            XCTAssertEqual(
                parameters.expectedCount / parameters.standardDeviation, criterion,
                accuracy: 1e-9
            )
        }
        // A stricter criterion needs a wider circle.
        let loose = KambParameters(sampleCount: 200, sigmaCriterion: 2)!
        let strict = KambParameters(sampleCount: 200, sigmaCriterion: 4)!
        XCTAssertLessThan(loose.countingCircleRadius, strict.countingCircleRadius)
    }

    /// A larger sample earns a smaller circle. That is the whole point of letting the
    /// data choose the smoothing.
    func testALargerSampleGetsASmallerCircle() {
        let radii = [20, 50, 100, 500, 1000].map {
            KambParameters(sampleCount: $0)!.countingCircleRadius
        }
        for (smaller, larger) in zip(radii, radii.dropFirst()) {
            XCTAssertGreaterThan(smaller, larger)
        }
        XCTAssertEqual(KambParameters(sampleCount: 100)!.countingCircleRadius, 23.447, accuracy: 1e-3)
        XCTAssertEqual(KambParameters(sampleCount: 1000)!.countingCircleRadius, 7.658, accuracy: 1e-3)
    }

    /// The numerical moments used for any weight must reproduce the hard circle's closed
    /// forms, `m₁ = m₂ = a`. If they do not, the smooth weight's σ scale is built on
    /// sand.
    func testNumericalMomentsReproduceTheClosedFormForTheHardCircle() {
        for sampleCount in [50, 200, 1000] {
            let area = 9 / Double(sampleCount + 9)
            let radius = acos(1 - area)
            let moments = KambParameters.moments(radius: radius, weighting: .kamb)
            XCTAssertEqual(moments.first, area, accuracy: 1e-6, "m₁ at N = \(sampleCount)")
            XCTAssertEqual(moments.second, area, accuracy: 1e-6, "m₂ at N = \(sampleCount)")
        }
    }

    /// The smooth weight is renormalized, not just substituted: the criterion still
    /// holds, and the radius comes out wider because a weight that fades at the edge has
    /// to reach further to gather the same statistic.
    func testTheSmoothWeightKeepsTheCriterionAndNeedsAWiderCircle() {
        for sampleCount in [50, 200, 1000] {
            let hard = KambParameters(sampleCount: sampleCount, weighting: .kamb)!
            let smooth = KambParameters(sampleCount: sampleCount, weighting: .modifiedKamb)!

            XCTAssertEqual(
                smooth.expectedCount / smooth.standardDeviation, 3,
                accuracy: 1e-3, "the criterion must survive the reweighting"
            )
            XCTAssertGreaterThan(smooth.countingCircleRadius, hard.countingCircleRadius)
        }
    }

    func testTheWeightProfile() {
        let parameters = KambParameters(sampleCount: 200, weighting: .kamb)!
        XCTAssertEqual(parameters.weight(atAxialAngle: 0), 1)
        XCTAssertEqual(parameters.weight(atAxialAngle: parameters.countingCircleRadius * 0.99), 1)
        XCTAssertEqual(parameters.weight(atAxialAngle: parameters.countingCircleRadius * 1.01), 0)

        let smooth = KambParameters(sampleCount: 200, weighting: .modifiedKamb)!
        XCTAssertEqual(smooth.weight(atAxialAngle: 0), 1, accuracy: 1e-12)
        XCTAssertEqual(smooth.weight(atAxialAngle: smooth.countingCircleRadius), 0, accuracy: 1e-12)
        // Monotonically decreasing, with no step at the edge.
        let half = smooth.weight(atAxialAngle: smooth.countingCircleRadius / 2)
        XCTAssertGreaterThan(half, 0)
        XCTAssertLessThan(half, 1)
    }

    func testTooFewAxesHaveNoParameters() {
        XCTAssertNil(KambParameters(sampleCount: 1))
        XCTAssertNil(KambParameters(sampleCount: 0))
        XCTAssertNil(KambParameters(sampleCount: 200, sigmaCriterion: 0))
        XCTAssertNotNil(KambParameters(sampleCount: 2))
    }
}

final class DensityFieldTests: XCTestCase {

    /// The cheapest check that the whole normalization is right, and the strictest:
    /// a sample with no preferred orientation must average to the σ criterion over the
    /// grid, because the grid samples the hemisphere by equal area.
    ///
    /// The sample is the golden-angle spiral, which is exactly area-uniform, so there is
    /// no sampling noise to hide behind — a pseudo-random sample would pass a looser
    /// version of this test.
    func testAUniformSampleAveragesToTheSigmaCriterion() {
        for sampleCount in [200, 400, 800] {
            for resolution in [21, 31, 41] {
                let grid = KambDensity.grid(
                    of: UniformAxialSample.axes(count: sampleCount), resolution: resolution
                )!
                XCTAssertEqual(
                    grid.mean, 3, accuracy: 0.05,
                    "N = \(sampleCount), \(resolution)×\(resolution) averaged \(grid.mean)σ"
                )
                XCTAssertEqual(grid.parameters.expectedCount / grid.parameters.standardDeviation, 3,
                               accuracy: 1e-9)
            }
        }
    }

    /// A uniform sample has nothing that stands out: nowhere on the net should look like
    /// a joint set.
    func testAUniformSampleHasNoPeak() {
        let grid = KambDensity.grid(of: UniformAxialSample.axes(count: 400), resolution: 31)!
        XCTAssertLessThan(grid.maximum, 5, "peaked at \(grid.maximum)σ on uniform data")
        XCTAssertGreaterThan(grid.minimum, 1)
    }

    /// And a real set must stand out unmistakably. A 200-pole cluster spread over 12°
    /// reaches tens of σ, against the 3σ a uniform sample gives.
    func testATightClusterPeaksFarAboveTheUniformExpectation() {
        let axes = Self.cluster(
            count: 200, about: PlaneOrientation(dip: 45, dipDirection: 90).pole, spread: 12
        )
        let grid = KambDensity.grid(of: axes, resolution: 31)!
        XCTAssertGreaterThan(grid.maximum, 30, "peaked at only \(grid.maximum)σ")
        XCTAssertEqual(grid.mean, 3, accuracy: 0.3, "the mean is fixed by the normalization")

        // And the peak is where the cluster is. Compared with a little slack rather than
        // exactly: the grid samples the field, and a node a degree off centre can read
        // marginally higher than the centre itself, since a spiral cluster is only
        // approximately radially symmetric.
        let centre = KambDensity.density(
            at: PlaneOrientation(dip: 45, dipDirection: 90).pole, of: axes
        )!
        XCTAssertEqual(grid.maximum, centre, accuracy: centre * 0.05)
    }

    /// A looser cluster peaks lower. If it did not, the σ scale would carry no
    /// information about concentration.
    ///
    /// The spreads start at 20°, above the 16.9° counting circle this sample size earns.
    /// Below that the cluster fits **entirely inside** the circle, every node near the
    /// centre counts all 200 poles, and the density saturates at `N/σ` — so a cluster
    /// spread over 8° and one spread over 15° both read exactly 69.7σ. That ceiling is
    /// real and worth knowing about: once a set is tighter than the counting circle, the
    /// contour peak stops telling you how tight. Fisher's κ, in the next stage, is what
    /// answers that.
    func testALooserClusterPeaksLower() {
        let pole = PlaneOrientation(dip: 60, dipDirection: 200).pole
        let peaks = [20.0, 30, 40].map { spread in
            KambDensity.grid(of: Self.cluster(count: 200, about: pole, spread: spread))!.maximum
        }
        for (tighter, looser) in zip(peaks, peaks.dropFirst()) {
            XCTAssertGreaterThan(tighter, looser, "peaks were \(peaks)")
        }
    }

    /// The saturation ceiling, stated outright so nobody reads a capped peak as a
    /// measure of concentration.
    func testDensitySaturatesOnceTheSetIsTighterThanTheCountingCircle() {
        let pole = PlaneOrientation(dip: 45, dipDirection: 0).pole
        let parameters = KambParameters(sampleCount: 200)!
        let ceiling = 200 / parameters.standardDeviation

        for spread in [4.0, 8, 12] {
            XCTAssertLessThan(spread, parameters.countingCircleRadius)
            let centre = KambDensity.density(
                at: pole, of: Self.cluster(count: 200, about: pole, spread: spread)
            )!
            XCTAssertEqual(centre, ceiling, accuracy: 1e-9, "at a spread of \(spread)°")
        }
        XCTAssertEqual(ceiling, 69.67, accuracy: 0.01)
    }

    /// Axial throughout: flipping half the input must leave the field bit-identical, not
    /// merely close. Anything less means the module is treating poles as vectors
    /// somewhere.
    func testFlippingHalfTheInputLeavesTheFieldUnchanged() {
        let axes = Self.cluster(
            count: 150, about: PlaneOrientation(dip: 80, dipDirection: 10).pole, spread: 14
        )
        let flipped = axes.enumerated().map { $0.offset.isMultiple(of: 2) ? -$0.element : $0.element }

        for weighting in ContourWeighting.allCases {
            let original = KambDensity.grid(of: axes, resolution: 21, weighting: weighting)!
            let mirrored = KambDensity.grid(of: flipped, resolution: 21, weighting: weighting)!
            XCTAssertEqual(original.values, mirrored.values, "\(weighting) is not axial")
        }
    }

    /// Two sets must show two peaks, and the density read at each one must be high. This
    /// is what the grouping module in the next stage works from.
    func testTwoSetsProduceTwoDistinctPeaks() {
        let firstPole = PlaneOrientation(dip: 80, dipDirection: 0).pole
        let secondPole = PlaneOrientation(dip: 30, dipDirection: 180).pole
        let axes = Self.cluster(count: 120, about: firstPole, spread: 10)
            + Self.cluster(count: 120, about: secondPole, spread: 10)

        let atFirst = KambDensity.density(at: firstPole, of: axes)!
        let atSecond = KambDensity.density(at: secondPole, of: axes)!
        let between = KambDensity.density(
            at: (firstPole + secondPole).normalized!, of: axes
        )!

        XCTAssertGreaterThan(atFirst, 20)
        XCTAssertGreaterThan(atSecond, 20)
        XCTAssertLessThan(between, min(atFirst, atSecond) / 3, "the peaks are not separated")
    }

    func testNodesOutsideThePrimitiveHaveNoValue() {
        let grid = KambDensity.grid(of: UniformAxialSample.axes(count: 100), resolution: 11)!
        // The corners of the square grid fall outside the circle.
        XCTAssertNil(grid.value(column: 0, row: 0))
        XCTAssertNotNil(grid.value(column: 5, row: 5))
        XCTAssertNil(grid.value(column: -1, row: 0))
        XCTAssertNil(grid.value(column: 11, row: 0))
        for row in 0..<grid.resolution {
            for column in 0..<grid.resolution {
                let inside = grid.point(column: column, row: row).isInsidePrimitive
                XCTAssertEqual(grid.value(column: column, row: row) != nil, inside)
            }
        }
    }

    func testContourLevelsStraddleTheUniformExpectation() {
        let grid = KambDensity.grid(
            of: Self.cluster(count: 200, about: Vector3(0, 0, -1), spread: 15), resolution: 31
        )!
        let levels = grid.contourLevels
        XCTAssertEqual(levels.first, 2)
        XCTAssertTrue(levels.contains(4))
        XCTAssertLessThanOrEqual(levels.last!, grid.maximum)
        // The uniform expectation sits between the first two levels, so a contour above
        // 4σ means something the rock did rather than something the sampling did.
        XCTAssertTrue(levels.contains { $0 < 3 } && levels.contains { $0 > 3 })
    }

    func testTooFewAxesProduceNoGrid() {
        XCTAssertNil(KambDensity.grid(of: []))
        XCTAssertNil(KambDensity.grid(of: [Vector3(0, 0, -1)]))
        XCTAssertNil(KambDensity.grid(of: [.zero, .zero, .zero]))
        XCTAssertNil(KambDensity.density(at: .upAxis, of: [Vector3(0, 0, -1)]))
        XCTAssertNil(KambDensity.density(at: .zero, of: UniformAxialSample.axes(count: 50)))
    }

    /// The smooth weight should round off the peak rather than move it.
    func testTheSmoothWeightingSmoothsWithoutShiftingThePeak() {
        // A spread wider than the counting circle, so the hard-edged version has a real
        // maximum rather than a saturated plateau whose argmax is arbitrary.
        let pole = PlaneOrientation(dip: 55, dipDirection: 310).pole
        let axes = Self.cluster(count: 200, about: pole, spread: 25)

        let hard = KambDensity.grid(of: axes, resolution: 31, weighting: .kamb)!
        let smooth = KambDensity.grid(of: axes, resolution: 31, weighting: .modifiedKamb)!

        func peakPoint(_ grid: DensityGrid) -> StereonetPoint {
            var best = StereonetPoint(east: 0, north: 0)
            var bestValue = -Double.infinity
            for row in 0..<grid.resolution {
                for column in 0..<grid.resolution {
                    if let value = grid.value(column: column, row: row), value > bestValue {
                        bestValue = value
                        best = grid.point(column: column, row: row)
                    }
                }
            }
            return best
        }

        let hardPeak = peakPoint(hard)
        let smoothPeak = peakPoint(smooth)
        let separation = ((hardPeak.east - smoothPeak.east) * (hardPeak.east - smoothPeak.east)
            + (hardPeak.north - smoothPeak.north) * (hardPeak.north - smoothPeak.north)).squareRoot()
        // The grid spacing is 2/31 ≈ 0.065, so this allows the two peaks to land about a
        // cell and a half apart — close enough to be the same feature, far from the
        // 0.5-plus a genuinely shifted peak would give.
        XCTAssertLessThan(separation, 0.15, "the smooth weight moved the peak")
        XCTAssertEqual(smooth.mean, 3, accuracy: 0.3)
    }

    // MARK: - Deterministic test fabric

    /// A deterministic cluster about an axis: the golden-angle spiral squashed into a cap
    /// of the given angular spread, so density tests have no random seed to argue with.
    static func cluster(count: Int, about axis: Vector3, spread: Double) -> [Vector3] {
        let mean = axis.normalized!
        let reference = abs(mean.x) < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0)
        let a = reference.cross(mean).normalized!
        let b = mean.cross(a)
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let limit = GeoAngle.radians(fromDegrees: spread)

        return (0..<count).map { index in
            // √ of the fraction spreads the points evenly over the cap's area.
            let theta = (Double(index) + 0.5).squareRoot() / Double(count).squareRoot() * limit
            let phi = Double(index) * golden
            return mean * cos(theta) + (a * cos(phi) + b * sin(phi)) * sin(theta)
        }
    }
}

final class UniformAxialSampleTests: XCTestCase {

    /// The spiral has to actually be uniform, or every test that leans on it is weaker
    /// than it looks. A uniform axial fabric has all three orientation-tensor eigenvalues
    /// at 1/3.
    func testTheSpiralIsUniform() {
        for count in [200, 800] {
            let axes = UniformAxialSample.axes(count: count)
            XCTAssertEqual(axes.count, count)
            let eigen = SymmetricMatrix3.orientationTensor(of: axes)!.eigen()
            for value in eigen.values {
                XCTAssertEqual(value, 1.0 / 3, accuracy: 0.01, "λ = \(eigen.values)")
            }
        }
    }

    func testEveryAxisIsAUnitVectorInTheLowerHemisphere() {
        for axis in UniformAxialSample.axes(count: 100) {
            XCTAssertEqual(axis.length, 1, accuracy: 1e-12)
            XCTAssertLessThanOrEqual(axis.up, 1e-12)
        }
    }

    func testEmptyRequest() {
        XCTAssertTrue(UniformAxialSample.axes(count: 0).isEmpty)
        XCTAssertTrue(UniformAxialSample.axes(count: -5).isEmpty)
    }
}
