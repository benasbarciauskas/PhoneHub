import XCTest
@testable import PhoneHubCore

final class AutomationRunPolicyTests: XCTestCase {
    func testStepsToRunSelectsCondensedOrRawWithFallback() {
        let condensed = AutomationStep.pressHome(id: UUID())
        let raw = AutomationStep.pressBack(id: UUID())
        var automation = Automation(name: "A", platform: .ios, steps: [condensed], rawSteps: [raw])
        XCTAssertEqual(stepsToRun(automation: automation), [condensed])
        automation.useCondensed = false
        XCTAssertEqual(stepsToRun(automation: automation), [raw])
        automation.rawSteps = nil
        XCTAssertEqual(stepsToRun(automation: automation), [condensed])
    }

    func testNextIterationHonorsLoopMode() {
        XCTAssertNil(nextIteration(loop: .once, current: 0))
        XCTAssertEqual(nextIteration(loop: .times(2), current: 0), 1)
        XCTAssertNil(nextIteration(loop: .times(2), current: 1))
        XCTAssertNil(nextIteration(loop: .times(0), current: 0))
        XCTAssertEqual(nextIteration(loop: .forever, current: 41), 42)
    }

    func testDefaultSettleIsFiveHundredMilliseconds() {
        XCTAssertEqual(automationSettleMilliseconds, 500)
    }
}
