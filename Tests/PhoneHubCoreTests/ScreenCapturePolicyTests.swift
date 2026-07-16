import XCTest
@testable import PhoneHubCore

final class ScreenCapturePolicyTests: XCTestCase {
    func testCasesProvidePickerLabelsAndDescriptions() {
        XCTAssertEqual(
            ScreenCapturePolicy.allCases,
            [.duringRunsOnly, .disabled, .always]
        )
        XCTAssertEqual(ScreenCapturePolicy.duringRunsOnly.displayName, "During Runs Only")
        XCTAssertEqual(ScreenCapturePolicy.disabled.displayName, "Disabled")
        XCTAssertEqual(ScreenCapturePolicy.always.displayName, "Always")
        XCTAssertFalse(ScreenCapturePolicy.allCases.contains { $0.description.isEmpty })
    }

    func testDuringRunsOnlyAllowsCaptureOnlyWhileRunIsActive() {
        XCTAssertTrue(screenCaptureDecision(
            policy: .duringRunsOnly, isRunActive: true
        ).allowsCapture)
        XCTAssertFalse(screenCaptureDecision(
            policy: .duringRunsOnly, isRunActive: false
        ).allowsCapture)
    }

    func testDisabledDeniesAllCaptureToolsEvenDuringRun() {
        let decision = screenCaptureDecision(policy: .disabled, isRunActive: true)

        XCTAssertFalse(decision.allowsCapture)
        XCTAssertEqual(decision.deniedTools, [
            "screenshot", "start_recording", "stop_recording"
        ])
        XCTAssertEqual(
            decision.logMessage,
            "screen capture disabled in settings — using text description only"
        )
    }

    func testAlwaysAllowsCaptureInsideAndOutsideRun() {
        XCTAssertTrue(screenCaptureDecision(
            policy: .always, isRunActive: true
        ).allowsCapture)
        XCTAssertTrue(screenCaptureDecision(
            policy: .always, isRunActive: false
        ).allowsCapture)
    }

    func testDuringRunsOnlyDenialExplainsInactiveRun() {
        let decision = screenCaptureDecision(
            policy: .duringRunsOnly, isRunActive: false
        )

        XCTAssertEqual(decision.deniedTools, [
            "screenshot", "start_recording", "stop_recording"
        ])
        XCTAssertEqual(
            decision.logMessage,
            "screen capture is limited to active runs — using text description only"
        )
    }
}
