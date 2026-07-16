import CoreGraphics
import XCTest
@testable import PhoneHubCore

final class HumanRecordingTests: XCTestCase {
    func testShortStationaryClickBecomesTapAfterDoubleClickWindow() {
        var translator = HumanRecordingTranslator()

        XCTAssertTrue(translator.consume(.leftMouseDown(time: 1, point: point(10, 20))).isEmpty)
        XCTAssertTrue(translator.consume(.leftMouseUp(time: 1.2, point: point(12, 23))).isEmpty)
        let steps = translator.consume(.idle(time: 1.56))

        assertTap(steps, x: 120, y: 230)
    }

    func testNearbyClicksWithinWindowCoalesceToDoubleTap() {
        var translator = HumanRecordingTranslator()
        _ = translator.consume(.leftMouseDown(time: 1, point: point(10, 20)))
        _ = translator.consume(.leftMouseUp(time: 1.1, point: point(10, 20)))
        _ = translator.consume(.leftMouseDown(time: 1.3, point: point(15, 24)))
        let steps = translator.consume(.leftMouseUp(time: 1.4, point: point(15, 24)))

        XCTAssertEqual(steps.count, 1)
        guard case let .doubleTap(_, label, x, y) = steps[0] else {
            return XCTFail("Expected double tap, got \(steps)")
        }
        XCTAssertNil(label)
        XCTAssertEqual(x, 150)
        XCTAssertEqual(y, 240)
    }

    func testDistantSecondClickFlushesFirstTap() {
        var translator = HumanRecordingTranslator()
        _ = translator.consume(.leftMouseDown(time: 0, point: point(10, 20)))
        _ = translator.consume(.leftMouseUp(time: 0.1, point: point(10, 20)))
        _ = translator.consume(.leftMouseDown(time: 0.3, point: point(30, 40)))
        let first = translator.consume(.leftMouseUp(time: 0.4, point: point(30, 40)))
        let second = translator.consume(.idle(time: 0.8))

        assertTap(first, x: 100, y: 200)
        assertTap(second, x: 300, y: 400)
    }

    func testStationaryPressAtLeastSixHundredMillisecondsBecomesLongPress() {
        var translator = HumanRecordingTranslator()
        _ = translator.consume(.leftMouseDown(time: 2, point: point(5, 8)))
        let steps = translator.consume(.leftMouseUp(time: 2.725, point: point(6, 8)))

        XCTAssertEqual(steps.count, 1)
        guard case let .longPress(_, _, x, y, durationMs) = steps[0] else {
            return XCTFail("Expected long press, got \(steps)")
        }
        XCTAssertEqual(x, 60)
        XCTAssertEqual(y, 80)
        XCTAssertEqual(durationMs, 725)
    }

    func testLargeMovementBecomesDominantDirectionSwipe() {
        var horizontal = HumanRecordingTranslator()
        _ = horizontal.consume(.leftMouseDown(time: 0, point: point(10, 10)))
        XCTAssertEqual(swipeDirection(horizontal.consume(
            .leftMouseUp(time: 0.2, point: point(55, 25))
        )), "right")

        var vertical = HumanRecordingTranslator()
        _ = vertical.consume(.leftMouseDown(time: 0, point: point(10, 60)))
        XCTAssertEqual(swipeDirection(vertical.consume(
            .leftMouseUp(time: 0.2, point: point(15, 10))
        )), "up")
    }

    func testAmbiguousPressesAreDiscardedInsteadOfGuessed() {
        var translator = HumanRecordingTranslator()
        _ = translator.consume(.leftMouseDown(time: 0, point: point(10, 10)))
        XCTAssertTrue(translator.consume(.leftMouseUp(time: 0.45, point: point(10, 10))).isEmpty)
        _ = translator.consume(.leftMouseDown(time: 1, point: point(10, 10)))
        XCTAssertTrue(translator.consume(.leftMouseUp(time: 1.1, point: point(25, 10))).isEmpty)
        XCTAssertTrue(translator.finish(at: 2).isEmpty)
    }

    func testScrollBurstCoalescesAndInvertsToFingerSwipe() {
        var translator = HumanRecordingTranslator()
        XCTAssertTrue(translator.consume(.scroll(time: 0, deltaX: 2, deltaY: 12)).isEmpty)
        XCTAssertTrue(translator.consume(.scroll(time: 0.25, deltaX: 1, deltaY: 20)).isEmpty)
        XCTAssertTrue(translator.consume(.idle(time: 0.64)).isEmpty)
        XCTAssertEqual(swipeDirection(translator.consume(.idle(time: 0.66))), "down")

        var horizontal = HumanRecordingTranslator()
        _ = horizontal.consume(.scroll(time: 0, deltaX: -30, deltaY: 2))
        XCTAssertEqual(swipeDirection(horizontal.finish(at: 1)), "left")
    }

    func testPrintableKeysFlushAsOneTextStepAfterTwoSecondsIdle() {
        var translator = HumanRecordingTranslator()
        _ = translator.consume(.printableKey(time: 1, text: "H"))
        _ = translator.consume(.printableKey(time: 1.1, text: "i"))
        XCTAssertTrue(translator.consume(.idle(time: 3.09)).isEmpty)
        let steps = translator.consume(.idle(time: 3.11))

        XCTAssertEqual(typeText(steps), "Hi")
    }

    func testDeleteEditsBufferThenRecordsDeleteWhenBufferIsEmpty() {
        var translator = HumanRecordingTranslator()
        _ = translator.consume(.printableKey(time: 0, text: "ab"))
        XCTAssertTrue(translator.consume(.deleteKey(time: 0.1)).isEmpty)
        XCTAssertEqual(typeText(translator.consume(.returnKey(time: 0.2))), "a")
        XCTAssertEqual(keyName(translator.consume(.deleteKey(time: 0.3))), "delete")
    }

    func testReturnFlushesTextThenRecordsReturnAndMouseFlushesText() {
        var translator = HumanRecordingTranslator()
        _ = translator.consume(.printableKey(time: 0, text: "hello"))
        let returned = translator.consume(.returnKey(time: 0.2))
        XCTAssertEqual(returned.count, 2)
        XCTAssertEqual(typeText([returned[0]]), "hello")
        XCTAssertEqual(keyName([returned[1]]), "return")

        _ = translator.consume(.printableKey(time: 1, text: "x"))
        let mouseBoundary = translator.consume(.rightMouseDown(time: 1.2))
        XCTAssertEqual(typeText(mouseBoundary), "x")
    }

    func testUnknownNonPrintableFlushesTextWithoutInventingAction() {
        var translator = HumanRecordingTranslator()
        _ = translator.consume(.printableKey(time: 0, text: "draft"))

        let steps = translator.consume(.nonPrintableKey(time: 0.2))

        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(typeText(steps), "draft")
    }

    func testStepGapsInsertRoundedCappedWaits() {
        var translator = HumanRecordingTranslator()
        _ = translator.consume(.leftMouseDown(time: 0, point: point(0, 0)))
        _ = translator.consume(.leftMouseUp(time: 0.1, point: point(0, 0)))
        _ = translator.consume(.idle(time: 0.5))
        _ = translator.consume(.leftMouseDown(time: 1.04, point: point(0, 0)))
        let rounded = translator.consume(.leftMouseUp(time: 1.7, point: point(0, 0)))
        XCTAssertEqual(waitMilliseconds(rounded), 900)

        _ = translator.consume(.leftMouseDown(time: 9, point: point(0, 0)))
        let capped = translator.consume(.leftMouseUp(time: 9.7, point: point(0, 0)))
        XCTAssertEqual(waitMilliseconds(capped), 5_000)
    }

    func testMapsIPhoneContentAndRejectsDerivedTitleBar() {
        let frame = CGRect(x: 100, y: 200, width: 410, height: 932)

        XCTAssertNil(mapIPhoneMirrorPoint(
            globalPoint: CGPoint(x: 200, y: 225), windowFrame: frame,
            contentSize: CGSize(width: 410, height: 898)
        ))
        let mapped = mapIPhoneMirrorPoint(
            globalPoint: CGPoint(x: 305, y: 683), windowFrame: frame,
            contentSize: CGSize(width: 410, height: 898)
        )
        XCTAssertEqual(mapped?.windowPoint, CGPoint(x: 205, y: 449))
        XCTAssertEqual(mapped?.devicePoint, CGPoint(x: 205, y: 449))
        XCTAssertNil(mapIPhoneMirrorPoint(
            globalPoint: CGPoint(x: 511, y: 683), windowFrame: frame,
            contentSize: CGSize(width: 410, height: 898)
        ))
    }

    func testMapsBorderlessAndroidWindowToFramebufferPixels() {
        let mapped = mapAndroidMirrorPoint(
            globalPoint: CGPoint(x: 280, y: 590),
            windowFrame: CGRect(x: 100, y: 200, width: 360, height: 780),
            devicePixelSize: CGSize(width: 1080, height: 2340)
        )

        XCTAssertEqual(mapped?.windowPoint, CGPoint(x: 180, y: 390))
        XCTAssertEqual(mapped?.devicePoint, CGPoint(x: 540, y: 1170))
    }

    func testParsesEffectiveAndroidWindowManagerSize() {
        XCTAssertEqual(
            parseAndroidWindowManagerSize("Physical size: 1080x2400\nOverride size: 720x1600\n"),
            CGSize(width: 720, height: 1600)
        )
        XCTAssertEqual(
            parseAndroidWindowManagerSize("Physical size: 1080x2400"),
            CGSize(width: 1080, height: 2400)
        )
        XCTAssertNil(parseAndroidWindowManagerSize("Physical size: 0x2400"))
        XCTAssertNil(parseAndroidWindowManagerSize("permission denied"))
    }

    func testClassifiesKeyboardTextWithoutRecordingShortcutsOrControls() {
        XCTAssertEqual(
            humanRecordedKeyEvent(time: 1, keyCode: 36, text: "\r",
                                  hasCommandOrControl: false),
            .returnKey(time: 1)
        )
        XCTAssertEqual(
            humanRecordedKeyEvent(time: 1, keyCode: 51, text: "",
                                  hasCommandOrControl: false),
            .deleteKey(time: 1)
        )
        XCTAssertEqual(
            humanRecordedKeyEvent(time: 1, keyCode: 0, text: "a",
                                  hasCommandOrControl: false),
            .printableKey(time: 1, text: "a")
        )
        XCTAssertEqual(
            humanRecordedKeyEvent(time: 1, keyCode: 0, text: "a",
                                  hasCommandOrControl: true),
            .nonPrintableKey(time: 1)
        )
        XCTAssertEqual(
            humanRecordedKeyEvent(time: 1, keyCode: 53, text: "\u{1b}",
                                  hasCommandOrControl: false),
            .nonPrintableKey(time: 1)
        )
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> HumanRecordingPoint {
        HumanRecordingPoint(
            windowPoint: CGPoint(x: x, y: y),
            devicePoint: CGPoint(x: x * 10, y: y * 10)
        )
    }

    private func assertTap(
        _ steps: [AutomationStep], x: Double, y: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(steps.count, 1, file: file, line: line)
        guard steps.count == 1, case let .tap(_, label, actualX, actualY) = steps[0] else {
            return XCTFail("Expected tap, got \(steps)", file: file, line: line)
        }
        XCTAssertNil(label, file: file, line: line)
        XCTAssertEqual(actualX, x, file: file, line: line)
        XCTAssertEqual(actualY, y, file: file, line: line)
    }

    private func swipeDirection(_ steps: [AutomationStep]) -> String? {
        steps.compactMap { step in
            guard case let .swipe(_, direction) = step else { return nil }
            return direction
        }.first
    }

    private func typeText(_ steps: [AutomationStep]) -> String? {
        steps.compactMap { step in
            guard case let .typeText(_, text) = step else { return nil }
            return text
        }.first
    }

    private func keyName(_ steps: [AutomationStep]) -> String? {
        steps.compactMap { step in
            guard case let .pressKey(_, key) = step else { return nil }
            return key
        }.first
    }

    private func waitMilliseconds(_ steps: [AutomationStep]) -> Int? {
        steps.compactMap { step in
            guard case let .wait(_, milliseconds) = step else { return nil }
            return milliseconds
        }.first
    }
}
