import XCTest
@testable import OrientationCore

/// A2 — stillness detection.
final class StillnessDetectorTests: XCTestCase {

    func testQuietHandHeldPhoneReadsAsStill() {
        var noise = TestNoise()
        var detector = StillnessDetector()
        for sample in motionStream(attitude: .identity, count: 20, userAcceleration: { _ in
            noise.vector(scale: 0.004)
        }) {
            detector.add(sample)
        }
        let assessment = detector.assessment
        XCTAssertTrue(assessment.isStill)
        XCTAssertTrue(assessment.hasVerdict)
        XCTAssertLessThan(assessment.accelerationStandardDeviation!, 0.02)
    }

    func testNoVerdictUntilTheWindowHasEnoughSamples() {
        var detector = StillnessDetector(criteria: StillnessCriteria(minimumSamples: 10))
        for sample in motionStream(attitude: .identity, count: 5) {
            detector.add(sample)
        }
        XCTAssertFalse(detector.assessment.hasVerdict)
        XCTAssertFalse(detector.assessment.isStill, "no verdict must not read as still")
        XCTAssertNil(detector.assessment.accelerationStandardDeviation)
        XCTAssertEqual(detector.assessment.sampleCount, 5)
    }

    /// The reason the detector uses the deviation of the acceleration **vector** and not
    /// of its magnitude: a phone being rocked steadily holds its magnitude almost
    /// constant while the direction swings. A magnitude-only test calls that still.
    func testSteadyRockingIsNotMistakenForStillness() {
        var detector = StillnessDetector()
        let samples = motionStream(attitude: .identity, count: 15, userAcceleration: { index in
            let phase = Double(index) * 0.7
            return Vector3(0.05 * cos(phase), 0.05 * sin(phase), 0)
        })
        for sample in samples { detector.add(sample) }

        // Every sample has the same magnitude, so a magnitude test would see zero spread.
        let magnitudes = samples.map { $0.userAcceleration.length }
        let meanMagnitude = magnitudes.reduce(0, +) / Double(magnitudes.count)
        let magnitudeSpread = magnitudes.reduce(0.0) { $0 + ($1 - meanMagnitude) * ($1 - meanMagnitude) }
        XCTAssertLessThan(magnitudeSpread, 1e-24, "the magnitudes really are constant")

        XCTAssertFalse(detector.assessment.isStill)
        XCTAssertGreaterThan(detector.assessment.accelerationStandardDeviation!, 0.02)
    }

    func testSlowRotationBlocksStillnessEvenWithoutLinearAcceleration() {
        var detector = StillnessDetector(criteria: StillnessCriteria(maximumRotationRate: 0.03))
        for sample in motionStream(attitude: .identity, count: 20, rotationRate: { _ in
            Vector3(0, 0, 0.1)                 // 5.7°/s about the screen axis
        }) {
            detector.add(sample)
        }
        XCTAssertFalse(detector.assessment.isStill)
        XCTAssertEqual(detector.assessment.peakRotationRate!, 0.1, accuracy: 1e-12)
    }

    func testWindowSlidesSoOldMovementStopsCountingAgainstYou() {
        var detector = StillnessDetector(criteria: StillnessCriteria(window: 0.3))
        // A quarter-second of shaking, then long enough quiet for it to leave the window.
        for sample in motionStream(attitude: .identity, count: 48, userAcceleration: { index in
            index < 16 ? Vector3(0.3, -0.2, 0.4) : .zero
        }) {
            detector.add(sample)
        }
        XCTAssertTrue(detector.assessment.isStill, "the shaking has left the window")
        XCTAssertLessThanOrEqual(detector.assessment.windowSpan, 0.3 + 1e-9)
    }

    func testResetClearsTheWindow() {
        var detector = StillnessDetector()
        for sample in motionStream(attitude: .identity, count: 20) { detector.add(sample) }
        XCTAssertTrue(detector.assessment.hasVerdict)
        detector.reset()
        XCTAssertEqual(detector.assessment.sampleCount, 0)
        XCTAssertFalse(detector.assessment.hasVerdict)
    }
}

/// A2 — burst collection and averaging.
final class BurstCollectorTests: XCTestCase {

    private func planeAttitude(dip: Double, dipDirection: Double, spin: Double = 0) -> Quaternion {
        deviceAttitude(forPlaneDip: dip, dipDirection: dipDirection, spin: spin)
    }

    func testBurstSettlesThenCollectsForTheRequestedDuration() {
        var collector = BurstCollector(target: .plane)
        let attitude = planeAttitude(dip: 42, dipDirection: 137)
        var statuses: [BurstCollector.Status] = []
        for sample in motionStream(attitude: attitude, count: 130) {
            statuses.append(collector.add(sample))
        }

        // Stillness needs 10 samples in the window, so collection starts at index 9 and
        // ends 1.5 s later at index 105: 97 samples at 64 Hz.
        guard case .settling = statuses[0] else { return XCTFail("should start by settling") }
        guard case .collecting = statuses[9] else { return XCTFail("should collect once still") }
        guard case .finished(let result) = collector.status else {
            return XCTFail("should have finished, got \(collector.status)")
        }

        XCTAssertEqual(result.sampleCount, 97)
        XCTAssertEqual(result.duration, 1.5, accuracy: 1e-12)
        XCTAssertEqual(result.effectiveSampleRate, 64, accuracy: 1e-9)
        XCTAssertEqual(result.target, .plane)
    }

    func testBurstAveragesToTheMeasuredPlane() {
        var collector = BurstCollector(target: .plane)
        for sample in motionStream(attitude: planeAttitude(dip: 42, dipDirection: 137), count: 130) {
            collector.add(sample)
        }
        guard case .finished(let result) = collector.status else { return XCTFail("not finished") }

        XCTAssertEqual(result.plane!.dip, 42, accuracy: requiredAccuracyDegrees)
        XCTAssertAzimuthEqual(result.plane!.dipDirection, 137, accuracy: requiredAccuracyDegrees)
        XCTAssertNil(result.line, "a planar burst has no lineation")
        XCTAssertEqual(result.angularStandardDeviation, 0, accuracy: 1e-9, "a fixed attitude has no scatter")
    }

    func testBurstAveragesToTheMeasuredLineation() {
        var collector = BurstCollector(target: .lineation)
        for sample in motionStream(
            attitude: deviceAttitude(forLineTrend: 212, plunge: 34, roll: 15), count: 130
        ) {
            collector.add(sample)
        }
        guard case .finished(let result) = collector.status else { return XCTFail("not finished") }

        XCTAssertEqual(result.line!.plunge, 34, accuracy: requiredAccuracyDegrees)
        XCTAssertAzimuthEqual(result.line!.trend, 212, accuracy: requiredAccuracyDegrees)
        XCTAssertNil(result.plane)
    }

    /// Scatter in the attitude has to show up in the reported standard deviation, or the
    /// figure is decoration.
    func testScatterInTheBurstIsReported() {
        var collector = BurstCollector(target: .plane)
        var timestamp = 0.0
        var index = 0
        while true {
            // Wobble the attitude by ±1° in dip.
            let wobble = 1.0 * sin(Double(index) * 0.5)
            let sample = MotionSample(
                timestamp: timestamp,
                attitude: planeAttitude(dip: 42 + wobble, dipDirection: 137)
            )
            if case .finished = collector.add(sample) { break }
            timestamp += 1.0 / 64
            index += 1
            if index > 1000 { return XCTFail("burst never finished") }
        }
        guard case .finished(let result) = collector.status else { return XCTFail("not finished") }
        XCTAssertGreaterThan(result.angularStandardDeviation, 0.5)
        XCTAssertLessThan(result.angularStandardDeviation, 1.5)
        XCTAssertEqual(result.plane!.dip, 42, accuracy: 0.3)
    }

    /// The measured direction keeps its sign, which is what records the face touched.
    func testMeasuredDirectionFollowsThePlacement() {
        let attitude = Quaternion(
            deviceXInWorld: .upAxis, deviceYInWorld: .northAxis, deviceZInWorld: .westAxis
        )!
        for placement in [DevicePlacement.leftSideOnFace, .rightSideOnFace] {
            var collector = BurstCollector(
                target: .plane,
                geometry: MeasurementGeometry(placement: placement, edge: .leftEdge)
            )
            for sample in motionStream(attitude: attitude, count: 130) { collector.add(sample) }
            guard case .finished(let result) = collector.status else { return XCTFail("not finished") }

            XCTAssertEqual(result.plane!.dip, 0, accuracy: 1e-9, "the phone is on a horizontal surface")
            // Left side down: the outward normal points up. Right side down: it points down.
            let expectedUp = placement == .leftSideOnFace ? 1.0 : -1.0
            XCTAssertEqual(result.measuredDirection.up, expectedUp, accuracy: 1e-9)
        }
    }

    func testMovementDuringTheBurstDiscardsItAndStartsAgain() {
        var collector = BurstCollector(target: .plane)
        let attitude = planeAttitude(dip: 30, dipDirection: 90)

        var sawRestart = false
        var timestamp = 0.0
        for _ in 0..<400 {
            // A jolt between 0.5 s and 0.6 s, quiet otherwise.
            let jolt = timestamp > 0.5 && timestamp < 0.6
            let status = collector.add(
                MotionSample(
                    timestamp: timestamp,
                    attitude: attitude,
                    userAcceleration: jolt ? Vector3(0.5, -0.4, 0.3) : .zero
                )
            )
            if case .restarted = status { sawRestart = true }
            if case .finished = status { break }
            timestamp += 1.0 / 64
        }

        XCTAssertTrue(sawRestart, "the jolt should have discarded the burst")
        guard case .finished(let result) = collector.status else {
            return XCTFail("should have recovered and finished, got \(collector.status)")
        }
        // The burst that survived began after the jolt, so it holds no jolted samples.
        XCTAssertEqual(result.duration, 1.5, accuracy: 1e-9)
        XCTAssertEqual(result.plane!.dip, 30, accuracy: requiredAccuracyDegrees)
    }

    func testMovementIsToleratedWhenTheCallerAsksForThat() {
        var collector = BurstCollector(
            target: .plane,
            criteria: BurstCriteria(requiresStillnessThroughout: false)
        )
        let attitude = planeAttitude(dip: 30, dipDirection: 90)
        for sample in motionStream(attitude: attitude, count: 130, userAcceleration: { index in
            index > 40 && index < 50 ? Vector3(0.5, -0.4, 0.3) : .zero
        }) {
            collector.add(sample)
        }
        guard case .finished = collector.status else { return XCTFail("should have finished anyway") }
    }

    /// A stream that fails to deliver the requested rate still produces a usable
    /// average, flagged so the shortfall is visible rather than silent.
    func testShortfallInSampleRateIsFlaggedNotHidden() {
        // The stillness window has to be long enough to fill at the slow rate, or the
        // burst would never start — 0.5 s at 32 Hz is 16 samples.
        var collector = BurstCollector(
            target: .plane,
            criteria: BurstCriteria(requestedSampleRate: 50, duration: 1.5),
            stillness: StillnessCriteria(window: 0.5)
        )
        for sample in motionStream(attitude: planeAttitude(dip: 20, dipDirection: 10), count: 70, rate: 32) {
            collector.add(sample)
        }
        guard case .finished(let result) = collector.status else { return XCTFail("not finished") }
        XCTAssertEqual(result.sampleCount, 49)
        XCTAssertEqual(result.effectiveSampleRate, 32, accuracy: 1e-9)
        XCTAssertFalse(result.meetsRequestedSampleRate)
        XCTAssertEqual(result.plane!.dip, 20, accuracy: requiredAccuracyDegrees)
    }

    func testRequestedRateIsMetWhenTheStreamKeepsUp() {
        var collector = BurstCollector(
            target: .plane,
            criteria: BurstCriteria(requestedSampleRate: 50, duration: 1.5)
        )
        for sample in motionStream(attitude: .identity, count: 130, rate: 64) {
            collector.add(sample)
        }
        guard case .finished(let result) = collector.status else { return XCTFail("not finished") }
        XCTAssertTrue(result.meetsRequestedSampleRate)
    }

    /// A caller that leaves the motion stream running must not be able to disturb a
    /// finished burst.
    func testSamplesAfterCompletionAreIgnored() {
        var collector = BurstCollector(target: .plane)
        for sample in motionStream(attitude: planeAttitude(dip: 55, dipDirection: 200), count: 130) {
            collector.add(sample)
        }
        guard case .finished(let before) = collector.status else { return XCTFail("not finished") }

        for sample in motionStream(
            attitude: planeAttitude(dip: 5, dipDirection: 10), count: 50, startingAt: 100
        ) {
            collector.add(sample)
        }
        guard case .finished(let after) = collector.status else { return XCTFail("no longer finished") }
        XCTAssertEqual(before, after)
        XCTAssertEqual(after.plane!.dip, 55, accuracy: requiredAccuracyDegrees)
    }

    func testResetStartsOver() {
        var collector = BurstCollector(target: .plane)
        for sample in motionStream(attitude: .identity, count: 130) { collector.add(sample) }
        guard case .finished = collector.status else { return XCTFail("not finished") }
        collector.reset()
        guard case .settling(let assessment) = collector.status else { return XCTFail("not settling") }
        XCTAssertEqual(assessment.sampleCount, 0)
    }

    func testMeasuredAxisDependsOnTargetAndGeometry() {
        let geometry = MeasurementGeometry(placement: .leftSideOnFace, edge: .bottomEdge)
        XCTAssertEqual(BurstCollector(target: .plane, geometry: geometry).measuredAxis, .plusX)
        XCTAssertEqual(BurstCollector(target: .lineation, geometry: geometry).measuredAxis, .plusX)
        let other = MeasurementGeometry(placement: .backOnFace, edge: .leftEdge)
        XCTAssertEqual(BurstCollector(target: .plane, geometry: other).measuredAxis, .plusZ)
        XCTAssertEqual(BurstCollector(target: .lineation, geometry: other).measuredAxis, .plusY)
    }
}
